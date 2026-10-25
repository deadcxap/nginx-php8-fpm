#!/usr/bin/env bash
set -Eeuo pipefail
archive_dir=${1:?Usage: publish-images.sh ARCHIVE_DIRECTORY}
repository="ghcr.io/${REPOSITORY:?Set REPOSITORY to owner/repository}"
repository=${repository,,}
declare -A version_tags
version_pattern='[0-9]+\.[0-9]+\.[0-9]+'

# Version tags are recorded on the native build runners from the tested images.
# Validate all artifacts before publishing anything; the publishing host does
# not need emulation to run the arm64 images.
for variant in with-node without-node; do
    tag_pattern="^nginx${version_pattern}_php${version_pattern}"
    if [[ "$variant" == with-node ]]; then tag_pattern+="_node${version_pattern}"; fi
    tag_pattern+='$'
    for arch in amd64 arm64; do
        archive="$archive_dir/image-$variant-$arch.tar"
        tag_file="$archive_dir/image-$variant-$arch.tag"
        if [[ ! -s "$archive" || ! -s "$tag_file" ]]; then
            echo "Missing image archive or version tag for $variant/$arch." >&2
            exit 1
        fi
        version_tag=$(< "$tag_file")
        if [[ ! "$version_tag" =~ $tag_pattern ]] || (( ${#version_tag} > 122 )); then
            echo "Invalid version tag for $variant/$arch: $version_tag" >&2
            exit 1
        fi
        if [[ -n "${version_tags[$variant]:-}" && "${version_tags[$variant]}" != "$version_tag" ]]; then
            echo "Runtime versions differ between architectures for $variant." >&2
            exit 1
        fi
        version_tags[$variant]=$version_tag
    done
done

# Only artifacts from this successful workflow run reach this job.
# No docker build runs after testing or scanning.
for variant in with-node without-node; do
    for arch in amd64 arm64; do
        docker load --input "$archive_dir/image-$variant-$arch.tar"
        platform=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "local/nginx-php8-fpm:$variant-$arch")
        if [[ "$platform" != "linux/$arch" ]]; then
            echo "Unexpected platform for $variant/$arch: $platform" >&2
            exit 1
        fi
    done
done
for variant in with-node without-node; do
    for arch in amd64 arm64; do
        reference="$repository:${version_tags[$variant]}-$arch"
        docker tag "local/nginx-php8-fpm:$variant-$arch" "$reference"
        docker push "$reference"
    done
done
for variant in with-node without-node; do
    version_tag=${version_tags[$variant]}
    docker buildx imagetools create --tag "$repository:$version_tag" \
        "$repository:$version_tag-amd64" \
        "$repository:$version_tag-arm64"
done

# All four images passed their gates and both versioned manifests now exist.
docker buildx imagetools create --tag "$repository:latest-without-node" "$repository:${version_tags[without-node]}"
docker buildx imagetools create --tag "$repository:latest" "$repository:${version_tags[with-node]}"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    # Backticks below are literal Markdown, not shell command substitutions.
    # shellcheck disable=SC2016
    printf 'Published `%s:latest` → `%s` and `%s:latest-without-node` → `%s`.\n' \
        "$repository" "${version_tags[with-node]}" "$repository" "${version_tags[without-node]}" >> "$GITHUB_STEP_SUMMARY"
fi
