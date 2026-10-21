#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?Usage: image-info.sh IMAGE}
docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' "$image"
docker run --rm "$image" sh -ec '
    cat /etc/alpine-release
    php --version
    php --modules
    nginx -V
    composer --version
    if command -v node >/dev/null; then node --version; npm --version; fi
    apk info -v
'
