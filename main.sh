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
#                                   Init                                         #
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

##################################################################################
#                             Check for Updates                                 #
##################################################################################

# ToDo: Add Check if VM is running -> skip and log if VM is not running

CurrentVirtIOVersion=$(fetch_latest_virtio_version)
CurrentQEMUGAVersion=$(fetch_latest_qemu_ga_version)

for vmid in $(echo "$windows_vms" | jq -r 'keys[]'); do
  VirtIO_version=$(get_windows_virtio_version "$vmid")
  QEMU_GA_version=$(get_windows_QEMU_GA_version "$vmid")

  need_virtio=false
  need_qemu_ga=false

  # Only if update is available we set the flag to true
  if [[ "$need_virtio" == true || "$need_qemu_ga" == true ]]; then
    node=$(echo "$windows_vms" | jq -r --arg vmid "$vmid" '.[$vmid].node')
    
    if [[ "$need_virtio" == true && "$need_qemu_ga" == true ]]; then
      # Beide Updates verfügbar
      build_svg_update_nag "$vmid" "$VirtIO_version" "$CurrentVirtIOVersion" "$QEMU_GA_version" "$CurrentQEMUGAVersion" "$(date '+%Y-%m-%d')"
    elif [[ "$need_virtio" == true ]]; then
      # Nur VirtIO Update
      build_svg_virtio_update_nag "$vmid" "$VirtIO_version" "$CurrentVirtIOVersion" "$(date '+%Y-%m-%d')"
    else
      # Nur QEMU GA Update
      build_svg_qemu_ga_update_nag "$vmid" "$QEMU_GA_version" "$CurrentQEMUGAVersion" "$(date '+%Y-%m-%d')"
    fi
    
    update_vm_description_with_update_nag "$node" "$vmid" "$need_virtio" "$need_qemu_ga"
  fi
done
