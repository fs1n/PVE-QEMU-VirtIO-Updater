#!/usr/bin/env bash
#
# Module: check-vm-updates.sh (PVE-QEMU-VirtIO-Updater)
# Description: Checks VirtIO and QEMU Guest Agent versions on Proxmox VE Windows VMs and manages update nag banners
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: jq, curl, pvesh, qm, sed, awk, grep
# Environment: LOG_DIR, LOG_LEVEL, LOG_FORMAT, STATE_DIR, SVG_IMAGE_TEMPLATE
# Usage: ./check-vm-updates.sh [vmid ...]  (optional: limit to specific VM IDs)
#        Typically run via cron or systemd timer with no arguments.
#
# Description:
#   Orchestrates the complete workflow: initialization, dependency checking,
#   fetching latest versions from Fedora People Archive, checking running Windows VMs,
#   comparing versions, managing update notifications via SVG nags in Proxmox VE UI,
#   and persisting VM state for tracking updates across runs.
#   If VM IDs are passed as arguments, only those VMs are processed.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
ENV_FILE="$SCRIPT_DIR/.env"

# Optional: specific VM IDs to check (positional args); empty = check all
TARGET_VMIDS=("$@")

# Load environment overrides if they exist
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  . "$ENV_FILE"
#   set +o allexport # Currently removed to fix array sourcing issues
fi

# Source all functions in lib files
for lib_file in "$LIB_DIR"/*.func; do
  if [[ -f "$lib_file" ]]; then
    source "$lib_file"
  fi
done

##################################################################################
#                                   Init                                         #
##################################################################################

# Initialize state directory first so state functions can write to it
# Don't state handle this either, its a simple if not so there is not much performance lost by this check.
init_state_dir

init_logger \
  --log "${LOG_DIR:=$SCRIPT_DIR/logs}/proxmox_virtio_updater.log" \
  --level "${LOG_LEVEL:=info}" \
  --format "${LOG_FORMAT:=[%d] [%l] %m}" \
  --quiet \
  --journal \
  --tag "PVE-VirtIO-Updater"

# Checks for required dependencies and exits if any are missing
# Don't ever handly by state! I had the issue that dependencies went missing
# and the script then broke.
check_script_dependencies

##################################################################################
#                             Check for Updates                                 #
##################################################################################

windows_vms_all=$(get_windows_vms)
windows_vms=$(echo "$windows_vms_all" | jq 'to_entries | map(select(.value.status == "running")) | from_entries')

# Filter to requested VM IDs if any were specified as arguments
if [[ ${#TARGET_VMIDS[@]} -gt 0 ]]; then
    target_filter=$(printf '%s\n' "${TARGET_VMIDS[@]}" | jq -R . | jq -s .)
    windows_vms=$(echo "$windows_vms" | \
        jq --argjson ids "$target_filter" \
           'with_entries(select(.key as $k | ($ids | index($k)) != null))')
fi

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

  if should_show_nag "$vmid" "$VirtIO_version" "$CurrentVirtIOVersion" \
                     "$QEMU_GA_version" "$CurrentQEMUGAVersion" "$vmgenid"; then
    nag_status=0
  else
    nag_status=$?
  fi

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
      if [[ "${WEBHOOK_ENABLED:-false}" == "true" ]]; then
        add_hook "$vmid"
      fi
      ;;
    1)
      # No-op: do not modify nag state or artifacts; leave existing nag state as-is
      :
      ;;
    2)
      # Nag cleared: remove any nag artifacts and persist state
      remove_vm_nag "$node" "$vmid"
      save_vm_state "$vmid" "$VirtIO_version" "$QEMU_GA_version" "false" "$vmgenid"
      if [[ "${WEBHOOK_ENABLED:-false}" == "true" ]]; then
        remove_hook "$vmid"
      fi
      ;;
    *)
      # Unexpected status: be defensive
      log_warn "Unknown nag_status='$nag_status' for VM $vmid; saving state without nag."
      save_vm_state "$vmid" "$VirtIO_version" "$QEMU_GA_version" "false" "$vmgenid"
      ;;
  esac
done

log_info "Update check completed."
