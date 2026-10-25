#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?Usage: image-info.sh IMAGE}
docker image inspect --format '{{.Id}} {{.Os}}/{{.Architecture}}' "$image"
docker run --rm "$image" sh -ec '
    runtime-info
    printf "\n=== Installed packages ===\n"
    apk info -v
'
