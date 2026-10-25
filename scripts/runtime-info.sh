#!/usr/bin/env bash
set -Eeuo pipefail
if (( $# > 1 )) || [[ "${1:-}" != '' && "${1:-}" != --tag ]]; then
    echo 'Usage: runtime-info [--tag]' >&2
    exit 2
fi

# Inspect the installed binaries, independently of an application's directory.
cd /
nginx_version=$(nginx -v 2>&1)
nginx_version=${nginx_version#nginx version: nginx/}
php_version=$(php -r 'echo PHP_VERSION;')
node_version=
if command -v node >/dev/null; then
    node_version=$(node --version)
    node_version=${node_version#v}
fi

for component in nginx php node; do
    variable=${component}_version
    version=${!variable}
    [[ "$component" == node && -z "$version" ]] && continue
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Unexpected $component version: $version" >&2
        exit 1
    fi
done
version_tag="nginx${nginx_version}_php${php_version}"
if [[ -n "$node_version" ]]; then
    version_tag+="_node${node_version}"
fi
if [[ "${1:-}" == --tag ]]; then
    printf '%s\n' "$version_tag"
    exit 0
fi

printf '=== Runtime versions ===\n'
printf 'Image version tag: %s\n' "$version_tag"
printf 'Alpine Linux: %s\n' "$(cat /etc/alpine-release)"
printf 'nginx: %s\nPHP: %s\n' "$nginx_version" "$php_version"
composer --no-plugins --no-scripts --version
if [[ -n "$node_version" ]]; then
    printf 'Node.js: %s\nnpm: %s\n' "$node_version" "$(npm --version)"
else
    printf 'Node.js/npm: not installed\n'
fi
printf '\n=== PHP modules ===\n'
php --modules
printf '\n=== nginx build options ===\n'
nginx -V 2>&1
printf '\n=== Installed nginx dynamic modules ===\n'
apk info -v | awk '/^nginx-module-/ { print }' | sort
printf '=== End runtime information ===\n'
