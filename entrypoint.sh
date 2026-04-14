#!/usr/bin/env bash
#
# entrypoint.sh — Docker container startup for PVE-QEMU-VirtIO-Updater
#
# Runs check-vm-updates.sh on a configurable interval (UPDATER_INTERVAL seconds,
# default 3600). The loop executes once immediately on startup, then sleeps.
# Errors in check-vm-updates.sh are logged but do not stop the loop.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${UPDATER_INTERVAL:-3600}"

# Ensure runtime directories exist (volumes may overlay these, so recreate if needed)
mkdir -p "${SCRIPT_DIR}/images" "${SCRIPT_DIR}/logs" "${SCRIPT_DIR}/.state"

echo "[entrypoint] PVE-QEMU-VirtIO-Updater container starting"
echo "[entrypoint] Update interval: ${INTERVAL}s"
echo "[entrypoint] PVE host: ${PVE_HOST:-<not set>}"
echo "[entrypoint] NAG_IMAGE_BASE_URL: ${NAG_IMAGE_BASE_URL:-<not set>}"

while true; do
    echo "[entrypoint] Running check-vm-updates.sh at $(date '+%Y-%m-%d %H:%M:%S')"
    "${SCRIPT_DIR}/check-vm-updates.sh" || echo "[entrypoint] check-vm-updates.sh exited with error $?"
    echo "[entrypoint] Sleeping ${INTERVAL}s until next run"
    sleep "$INTERVAL"
done
