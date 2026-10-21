#!/usr/bin/env bash
set -Eeuo pipefail
archive_dir=${1:?Usage: publish-images.sh ARCHIVE_DIRECTORY}
repository="ghcr.io/${REPOSITORY:?Set REPOSITORY to owner/repository}"
repository=${repository,,}
build_tag=${BUILD_TAG:?Set BUILD_TAG to a unique build identifier}

# Only artifacts from this successful workflow run reach this job.
# No docker build runs after testing or scanning.
for variant in with-node without-node; do
    for arch in amd64 arm64; do
        docker load --input "$archive_dir/image-$variant-$arch.tar"
        reference="$repository:$build_tag-$variant-$arch"
        docker tag "local/nginx-php8-fpm:$variant-$arch" "$reference"
        docker push "$reference"
    done
    if [[ "$variant" == with-node ]]; then suffix=; else suffix=-without-node; fi
    docker buildx imagetools create --tag "$repository:$build_tag$suffix" \
        "$repository:$build_tag-$variant-amd64" \
        "$repository:$build_tag-$variant-arm64"
done

# All four images passed their gates and both versioned manifests now exist.
docker buildx imagetools create --tag "$repository:without-node" "$repository:$build_tag-without-node"
docker buildx imagetools create --tag "$repository:latest" "$repository:$build_tag"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    # Backticks below are literal Markdown, not shell command substitutions.
    # shellcheck disable=SC2016
    printf 'Published `%s:latest` and `%s:without-node`.\n\nRollback tags: `%s` and `%s-without-node`.\n' \
        "$repository" "$repository" "$build_tag" "$build_tag" >> "$GITHUB_STEP_SUMMARY"
fi
