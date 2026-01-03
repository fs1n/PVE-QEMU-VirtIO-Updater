#!/bin/env bash
# Proxmox VE VirtIO Updater Script on Host

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

for file in "$LIB_DIR"/*.sh; do
  [ -f "$file" ] || continue
  . "$file"
done

# Load environment overrides if they exist
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  . "$ENV_FILE"
  set +o allexport
fi

##################################################################################
# Init                                                                           #
##################################################################################

init_logger \
  --log "${LOG_DIR:=$SCRIPT_DIR/logs}/proxmox_virtio_updater.log" \
  --level "${LOG_LEVEL:=info}" \
  --format "${LOG_FORMAT:=[%d] [%l] %m}" \
  --quiet \
  --journal \
  --tag "PVE-VirtIO-Updater"

check_script_dependencies

windows_vms=$(get_windows_vms)
if [[ -z "$windows_vms" || "$windows_vms" == "{}" ]]; then
    log_info "No Windows VMs found on this Proxmox host. Exiting."
    exit 0
fi

for vmid in $(echo "$windows_vms" | jq -r 'keys[]'); do
    VirtIO_version=$(get_windows_virtio_version "$vmid")
    QEMU_GA_version=$(get_windows_QEMU_GA_version "$vmid")

    # Write to JSON database
    update_data_json "$vmid" "current_VirtIO_version" "$VirtIO_version"
    update_data_json "$vmid" "current_QEMU_GA_version" "$QEMU_GA_version"
done

    