#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

target=${TARGET:-with-node}
case "$target" in
    with-node) default_tag=latest ;;
    without-node) default_tag=without-node ;;
    *) echo 'TARGET must be with-node or without-node.' >&2; exit 1 ;;
esac
image=${IMAGE:-ghcr.io/deadcxap/nginx-php8-fpm:$default_tag}
php_image=${PHP_IMAGE:-php:fpm-alpine}
platform=${PLATFORM:-linux/$(docker info --format '{{.Architecture}}')}
case "$platform" in
    linux/x86_64) platform=linux/amd64 ;;
    linux/aarch64) platform=linux/arm64 ;;
esac

# Resolve today's PHP image once, then use that same digest for probing/building.
docker pull --platform "$platform" "$php_image"
php_digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "$php_image")
node_image=${NODE_IMAGE:-node:lts-alpine}
if [[ "$target" == with-node && -z "${NODE_IMAGE:-}" ]]; then
    node_channel=${NODE_CHANNEL:-lts}
    case "$node_channel" in
        lts|current) ;;
        *) echo 'NODE_CHANNEL must be lts or current.' >&2; exit 1 ;;
    esac
    alpine_release=$(docker run --rm --platform "$platform" --entrypoint cat "$php_digest" /etc/alpine-release)
    node_image="node:${node_channel}-alpine$(cut -d. -f1,2 <<< "$alpine_release")"
fi

exec docker buildx build --pull --no-cache --load \
    --platform "$platform" --target "$target" --tag "$image" \
    --build-arg "PHP_IMAGE=$php_digest" \
    --build-arg "NODE_IMAGE=$node_image" \
    --build-arg "APKMIRROR=${APKMIRROR:-dl-cdn.alpinelinux.org}" \
    --build-arg "IMAGE_SOURCE=${IMAGE_SOURCE:-https://github.com/deadcxap/nginx-php8-fpm}" \
    --build-arg "IMAGE_REVISION=${IMAGE_REVISION:-$(git rev-parse HEAD)}" \
    --build-arg "IMAGE_CREATED=${IMAGE_CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
    --build-arg "IMAGE_VERSION=${IMAGE_VERSION:-local}" \
    "$@" .
