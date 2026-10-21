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
    rm -rf "$fixture_dir"
}
trap cleanup EXIT

docker run --rm --mount "type=bind,src=$PWD/tests/php-check.php,dst=/tmp/php-check.php,readonly" \
    "$image" php /tmp/php-check.php
docker run --rm "$image" composer --version
if [[ "$variant" == with-node ]]; then
    docker run --rm "$image" node -e 'if (require("node:crypto").randomBytes(16).length !== 16) process.exit(1)'
    docker run --rm "$image" npm --version
    docker run --rm "$image" npx --version
else
    docker run --rm "$image" sh -ec '! command -v node; ! command -v npm'
fi

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
docker exec "$container" supervisorctl status
echo "Smoke tests passed: $image ($variant)"
