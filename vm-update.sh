#!/usr/bin/env bash
#
# Module: vm-update.sh (PVE-QEMU-VirtIO-Updater)
# Description: Stub script executed by the adnanh/webhook server when an update is triggered
#              from the Proxmox UI. Receives VM ID as first argument.
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2026-04-07
#
# Usage: ./vm-update.sh <vmid>
#   Called automatically by the webhook server — do not invoke manually in production.
#
# TODO: Invoke Update-VirtIO-QemuGA inside the VM via qm exec once the integration is ready.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

VM_ID="${1:-}"
if [[ -z "$VM_ID" ]]; then
    echo "ERROR: No VM ID provided" >&2
    exit 1
fi

LOG_FILE="${SCRIPT_DIR}/logs/webhook.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Update triggered for VM ${VM_ID}" | tee -a "$LOG_FILE"

# TODO: Inject and run Update-VirtIO-QemuGA inside the VM:
# qm exec "${VM_ID}" -- powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\Update-VirtIO-QemuGA.ps1"
