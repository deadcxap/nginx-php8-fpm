#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
image=${1:?Usage: smoke-test.sh IMAGE [with-node|without-node]}
variant=${2:-with-node}
case "$variant" in with-node|without-node) ;; *) exit 2 ;; esac

container=
fixture_dir=$(mktemp -d)
cleanup() {
    status=$?
    if [[ -n "$container" ]]; then
        if (( status != 0 )); then docker logs "$container" >&2 || true; fi
        docker rm -f "$container" >/dev/null || true
    fi
    # Permission checks create files owned by container UIDs in this temp folder.
    docker run --rm --mount "type=bind,src=$fixture_dir,dst=/fixture" \
        "$image" chown -hR "$(id -u):$(id -g)" /fixture >/dev/null || true
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

docker run --rm --mount "type=bind,src=$PWD/tests/php-check.php,dst=/tmp/php-check.php,readonly" \
    "$image" php /tmp/php-check.php
docker run --rm "$image" composer --version
if [[ "$variant" == with-node ]]; then
    docker run --rm --mount "type=bind,src=$PWD/tests/npm-check.sh,dst=/tmp/npm-check.sh,readonly" \
        "$image" sh /tmp/npm-check.sh
else
    docker run --rm "$image" sh -ec '! command -v node; ! command -v npm'
fi
runtime_tag=$(docker run --rm "$image" runtime-info --tag)
expected_tag=$(docker run --rm "$image" sh -ec '
    nginx_version=$(nginx -v 2>&1)
    printf "nginx%s_php%s" "${nginx_version##*/}" "$(php -r "echo PHP_VERSION;")"
    if command -v node >/dev/null; then printf "_node%s" "$(node -p process.versions.node)"; fi
')
[[ "$runtime_tag" == "$expected_tag" ]]

check_startup_report() {
    local expected_count=$1 logs
    logs=$(docker logs "$container" 2>&1)
    [[ "$(grep -Fc '=== Runtime versions ===' <<< "$logs")" == "$expected_count" ]]
    [[ "$logs" == *"Image version tag: $runtime_tag"* ]]
    [[ "$logs" == *'Composer version '* && "$logs" == *'Alpine Linux: '* ]]
    [[ "$logs" == *'=== PHP modules ==='* && "$logs" == *$'\nredis\n'* && "$logs" == *$'\npdo_mysql\n'* ]]
    [[ "$logs" == *'=== nginx build options ==='* && "$logs" == *'nginx-module-xslt-'* ]]
    [[ "$logs" == *'=== End runtime information ==='* ]]
    if [[ "$variant" == with-node ]]; then
        [[ "$logs" == *'Node.js: '* && "$logs" == *'npm: '* ]]
    else
        [[ "$logs" == *'Node.js/npm: not installed'* && "$runtime_tag" != *_node* ]]
    fi
}

wait_for_php() {
    local expected=$1 response
    for ((attempt=0; attempt<60; attempt++)); do
        if response=$(docker exec "$container" curl --fail --silent --max-time 2 http://127.0.0.1/index.php); then
            if [[ "$response" != "$expected" ]]; then
                printf 'Unexpected PHP response: %s\nExpected: %s\n' "$response" "$expected" >&2
                return 1
            fi
            return 0
        fi
        sleep 1
    done
    echo 'PHP HTTP endpoint did not become ready.' >&2
    return 1
}

# Default startup and the standard web root.
container=$(docker create "$image")
docker cp tests/http-fixture.php "$container:/var/www/html/index.php"
docker start "$container" >/dev/null
wait_for_php '{"ok":true,"memory_limit":"128M","post_max_size":"100M","upload_max_filesize":"100M","timezone":"UTC"}'
check_startup_report 1
docker rm -f "$container" >/dev/null
container=

# Environment overrides, Laravel directories, static content and repeat startup.
mkdir -p "$fixture_dir/public"
cp tests/http-fixture.php "$fixture_dir/public/index.php"
printf 'static-ok' > "$fixture_dir/public/asset.txt"
container=$(docker create \
    -e WEBROOT=/var/www/html/public -e TZ=Europe/Moscow \
    -e PHP_MEM_LIMIT=256 -e PHP_POST_MAX_SIZE=64 -e PHP_UPLOAD_MAX_FILESIZE=32 \
    -e CREATE_LARAVEL_STORAGE=1 "$image")
docker cp "$fixture_dir/public" "$container:/var/www/html/public"
docker start "$container" >/dev/null
expected='{"ok":true,"memory_limit":"256M","post_max_size":"64M","upload_max_filesize":"32M","timezone":"Europe/Moscow"}'
wait_for_php "$expected"
[[ "$(docker exec "$container" curl --fail --silent http://127.0.0.1/asset.txt)" == static-ok ]]
[[ "$(docker exec "$container" curl --silent -o /dev/null -w '%{http_code}' http://127.0.0.1/missing.php)" == 404 ]]
headers=$(docker exec "$container" curl --fail --silent --head http://127.0.0.1/index.php)
if grep -Eiq '^(x-powered-by:|server: nginx/)' <<< "$headers"; then
    echo 'Default HTTP response leaks runtime versions.' >&2
    exit 1
fi
docker exec --user nginx "$container" test -w /var/www/html/storage/framework/cache/data
config_before=$(docker exec "$container" sha256sum /usr/local/etc/php/conf.d/zz-runtime.ini /usr/local/etc/php-fpm.d/zzz-app.conf)
docker restart --time 15 "$container" >/dev/null
wait_for_php "$expected"
config_after=$(docker exec "$container" sha256sum /usr/local/etc/php/conf.d/zz-runtime.ini /usr/local/etc/php-fpm.d/zzz-app.conf)
[[ "$config_before" == "$config_after" ]]
check_startup_report 2
docker exec "$container" supervisorctl status
docker rm -f "$container" >/dev/null
container=

# Exercise defaults and Unraid IDs against a real bind mount, including the
# existing Alpine GID 100, a non-default umask and restarting the same container.
for settings in '101:101:022:0644:0755' '99:100:022:0644:0755' \
                '99:100:0002:0664:0775' '99:100:077:0600:0700'; do
    IFS=: read -r worker_uid worker_gid mask file_mode directory_mode <<< "$settings"
    permission_dir="$fixture_dir/permissions-$worker_uid-$worker_gid-$mask"
    mkdir -p "$permission_dir/writable"
    chmod 755 "$permission_dir"
    cp tests/permissions-fixture.php "$permission_dir/index.php"
    docker run --rm --mount "type=bind,src=$permission_dir,dst=/fixture" "$image" \
        sh -ec 'chown "$1:$2" /fixture/writable; chmod 750 /fixture/writable' sh "$worker_uid" "$worker_gid"
    ownership_before=$(stat -c '%u:%g:%a' "$permission_dir" "$permission_dir/index.php" "$permission_dir/writable")
    runtime_options=()
    if [[ "$worker_uid" != 101 ]]; then
        runtime_options=(-e "PUID=$worker_uid" -e "PGID=$worker_gid" -e "UMASK=$mask")
    fi
    container=$(docker create "${runtime_options[@]}" \
        --mount "type=bind,src=$permission_dir,dst=/var/www/html" "$image")
    docker start "$container" >/dev/null
    expected=$(printf '{"uid":%s,"gid":%s,"umask":"%03o","file_uid":%s,"file_gid":%s,"file_mode":"%s","directory_mode":"%s"}' \
        "$worker_uid" "$worker_gid" "$((8#$mask))" "$worker_uid" "$worker_gid" "$file_mode" "$directory_mode")
    wait_for_php "$expected"
    # With UMASK=077 this also proves nginx workers have the same UID as PHP.
    [[ "$(docker exec "$container" curl --fail --silent http://127.0.0.1/writable/from-php.txt)" == written-by-php ]]
    docker restart --time 15 "$container" >/dev/null
    wait_for_php "$expected"
    ownership_after=$(stat -c '%u:%g:%a' "$permission_dir" "$permission_dir/index.php" "$permission_dir/writable")
    [[ "$ownership_before" == "$ownership_after" ]]
    docker rm -f "$container" >/dev/null
    container=
done

for invalid_setting in PUID=0 PGID=0 PUID=-1 PGID=invalid PUID=4294967295 UMASK=888 UMASK=00000; do
    if output=$(docker run --rm -e "$invalid_setting" "$image" 2>&1); then
        echo "Invalid setting was accepted: $invalid_setting" >&2
        exit 1
    fi
    [[ "$output" == *"${invalid_setting%%=*} must be"* ]]
done
echo 'Worker IDs, bind-mount permissions, umask and validation checks passed.'
echo "Smoke tests passed: $image ($variant)"
