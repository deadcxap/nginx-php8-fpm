#!/usr/bin/env bash
set -Eeuo pipefail
archive=$(realpath "${1:?Usage: scan-image.sh IMAGE_TAR REPORT_DIRECTORY}")
report_dir=${2:?Usage: scan-image.sh IMAGE_TAR REPORT_DIRECTORY}
mkdir -p "$report_dir"
report_dir=$(realpath "$report_dir")
scanner=${TRIVY_IMAGE:-aquasec/trivy:latest}
docker pull "$scanner"
# Use one scanner image for both the report and the gate.
scanner_id=$(docker image inspect --format '{{.Id}}' "$scanner")
options=(--rm --user "$(id -u):$(id -g)"
    --mount "type=bind,src=$archive,dst=/input/image.tar,readonly"
    --mount "type=bind,src=$report_dir,dst=/reports")
docker run "${options[@]}" "$scanner_id" image \
    --cache-dir /reports/cache --timeout 15m --scanners vuln \
    --input /input/image.tar --format json --output /reports/trivy.json
# Keep the full report above, including issues for which no fix is available.
docker run "${options[@]}" "$scanner_id" image \
    --cache-dir /reports/cache --timeout 15m --scanners vuln --skip-db-update \
    --input /input/image.tar --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1
