#!/usr/bin/env bash
#
# Deprecated wrapper for PatchMox.
# Use bin/patchmox directly for new deployments.
#
# Author: Frederik S. (fs1n) and PatchMox Contributors
# Date: 2026-07-15

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/bin/patchmox" check "$@"
