#!/bin/env bash
# Proxmox VE VirtIO Updater Script on Host

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

for file in "$LIB_DIR"/*.sh; do
  [ -f "$file" ] || continue   # skip if no matches found in directory
  . "$file"
done

# Script Defaults
: "${LOG_DIR:=$SCRIPT_DIR/logs}"
: "${LOG_LEVEL:=info}"
: "${LOG_FORMAT:="[%d] [%l] %m"}"

ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  # restrict format: KEY=VALUE lines, optional comments
  set -o allexport
  . "$ENV_FILE"
  set +o allexport
fi

# init

init_logger --logfile "$LOG_DIR/proxmox_virtio_updater.log" --loglevel "$LOG_LEVEL" --format "$LOG_FORMAT" --quiet --journal --tag "PVE-VirtIO-Updater"
