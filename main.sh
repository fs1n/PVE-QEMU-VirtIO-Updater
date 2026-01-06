#!/bin/env bash
# Proxmox VE VirtIO Updater Script on Host

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source all functions in lib files
for lib_file in "$LIB_DIR"/*.sh; do
  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  fi
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

# Initialize state directory
init_state_dir

##################################################################################
#                             Check for Updates                                 #
##################################################################################

windows_vms_all=$(get_windows_vms)  
windows_vms=$(echo "$windows_vms_all" | jq 'to_entries | map(select(.value.status == "running")) | from_entries')

if [[ -z "$windows_vms" || "$windows_vms" == "{}" ]]; then
    log_info "No Windows VMs found on this Proxmox host. Exiting."
    exit 0
fi

# Clean up state files for deleted VMs
cleanup_stale_state_files "$windows_vms_all"

virtio_info=$(fetch_latest_virtio_version)
CurrentVirtIOVersion=$(echo "$virtio_info" | jq -r '.version')
CurrentVirtIORelease=$(echo "$virtio_info" | jq -r '.release')

qemu_info=$(fetch_latest_qemu_ga_version)
CurrentQEMUGAVersion=$(echo "$qemu_info" | jq -r '.version')
CurrentQEMUGARelease=$(echo "$qemu_info" | jq -r '.release')

for vmid in $(echo "$windows_vms" | jq -r 'keys[]'); do
  node=$(echo "$windows_vms" | jq -r --arg vmid "$vmid" '.[$vmid].node')

  vmgenid=$(get_vm_genid "$node" "$vmid")

  VirtIO_version=$(get_windows_virtio_version "$vmid")
  QEMU_GA_version=$(get_windows_QEMU_GA_version "$vmid")

  need_virtio=false
  need_qemu_ga=false

  if [[ "$VirtIO_version" != "$CurrentVirtIOVersion" ]]; then
    need_virtio=true
  fi

  if [[ "$QEMU_GA_version" != "$CurrentQEMUGAVersion" ]]; then
    need_qemu_ga=true
  fi

  should_show_nag "$vmid" "$VirtIO_version" "$CurrentVirtIOVersion" \
                  "$QEMU_GA_version" "$CurrentQEMUGAVersion" "$vmgenid"
  nag_status=$?

  case "$nag_status" in
    0)
      # Auto: maybe show nag, depending on whether updates are needed
      maybe_show_update_nag \
        "$node" "$vmid" \
        "$need_virtio" "$need_qemu_ga" \
        "$VirtIO_version" "$CurrentVirtIOVersion" \
        "$QEMU_GA_version" "$CurrentQEMUGAVersion" \
        "$CurrentVirtIORelease" "$CurrentQEMUGARelease" \
        "$vmgenid"
      ;;
    1)
      # Nag muted: never show nag, just persist state
      save_vm_state "$vmid" "$VirtIO_version" "$QEMU_GA_version" "false" "$vmgenid"
      ;;
    2)
      # Nag cleared: remove any nag artifacts and persist state
      remove_vm_nag "$node" "$vmid"
      save_vm_state "$vmid" "$VirtIO_version" "$QEMU_GA_version" "false" "$vmgenid"
      ;;
    *)
      # Unexpected status: be defensive
      log_warn "Unknown nag_status='$nag_status' for VM $vmid; saving state without nag."
      save_vm_state "$vmid" "$VirtIO_version" "$QEMU_GA_version" "false" "$vmgenid"
      ;;
  esac
done

log_info "Update check completed."
