#!/usr/bin/env bash
set -Eeuo pipefail
export TARGET=without-node
exec "$(dirname "${BASH_SOURCE[0]}")/build.sh" "$@"
