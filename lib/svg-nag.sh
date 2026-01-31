#!/usr/bin/env bash
#
# Module: svg-nag.sh (PVE-QEMU-VirtIO-Updater)
# Description: SVG template rendering for update notifications displayed in Proxmox VE UI
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: sed, cp, mv
# Environment: SVG_IMAGE_PATH, SVG_IMAGE_TEMPLATE, SVG_IMAGE_TEMPLATE_BOTH, SCRIPT_DIR
# Usage: source lib/svg-nag.sh; build_svg_virtio_update_nag vmid current_ver latest_ver date
#
# Functions:
#   - build_svg_update_nag: Create SVG banner for both VirtIO and QEMU GA updates
#   - build_svg_virtio_update_nag: Create SVG banner for VirtIO updates only
#   - build_svg_qemu_ga_update_nag: Create SVG banner for QEMU GA updates only

SVG_IMAGE_PATH="/usr/share/pve-manager/images/"
SVG_IMAGE_TEMPLATE="${SCRIPT_DIR}/templates/svg/update-nag-template.svg"
SVG_IMAGE_TEMPLATE_BOTH="${SCRIPT_DIR}/templates/svg/update-nag-both-template.svg"

# @function build_svg_update_nag
# @description Generates SVG banner showing both VirtIO and QEMU GA update availability
# @args vmid (string): Proxmox VM ID
#       vmVirtIOCurrenetVersion (string): Currently installed VirtIO version
#       vmVirtIOLatestVersion (string): Latest available VirtIO version
#       vmQEMUGACurrenetVersion (string): Currently installed QEMU GA version
#       vmQEMUGALatestVersion (string): Latest available QEMU GA version
#       virtIOreleaseDate (string): VirtIO release date (YYYY-MM-DD)
#       qemuGAReleaseDate (string): QEMU GA release date (YYYY-MM-DD)
# @returns 0 on success, 1 on file operation error; writes SVG to /usr/share/pve-manager/images/update-{vmid}.svg
# @example
#   build_svg_update_nag 100 0.1.283 0.1.285 9.0.0 9.1.0 2025-01-15 2025-01-20
function build_svg_update_nag() {
    local vmid=$1
    local vmVirtIOCurrenetVersion=$2
    local vmVirtIOLatestVersion=$3
    local vmQEMUGACurrenetVersion=$4
    local vmQEMUGALatestVersion=$5
    local virtIOreleaseDate=$6
    local qemuGAReleaseDate=$7

    cp "${SVG_IMAGE_TEMPLATE_BOTH}" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
    
    sed -e "s/{{ title }}/VirtIO \&amp; QEMU GA Update Available/g" \
    -e "s/{{ current_version }}/${vmVirtIOCurrenetVersion}/g" \
    -e "s/{{ available_version }}/${vmVirtIOLatestVersion}/g" \
    -e "s/{{ virtio_release_date }}/${virtIOreleaseDate}/g" \
    -e "s/{{ qemu_ga_current_version }}/${vmQEMUGACurrenetVersion}/g" \
    -e "s/{{ qemu_ga_available_version }}/${vmQEMUGALatestVersion}/g" \
    -e "s/{{ qemu_ga_release_date }}/${qemuGAReleaseDate}/g" \
    "${SVG_IMAGE_PATH}/update-${vmid}.svg" > "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" && \
    mv "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
}

# @function build_svg_virtio_update_nag
# @description Generates SVG banner showing VirtIO update availability only
# @args vmid (string): Proxmox VM ID
#       vmVirtIOCurrenetVersion (string): Currently installed VirtIO version
#       vmVirtIOLatestVersion (string): Latest available VirtIO version
#       releaseDate (string): VirtIO release date (YYYY-MM-DD)
# @returns 0 on success, 1 on file operation error
# @example
#   build_svg_virtio_update_nag 100 0.1.283 0.1.285 2025-01-15
function build_svg_virtio_update_nag() {
    local vmid=$1
    local vmVirtIOCurrenetVersion=$2
    local vmVirtIOLatestVersion=$3
    local releaseDate=$4

    cp "${SVG_IMAGE_TEMPLATE}" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
    sed -e "s/{{ title }}/VirtIO Update Available/g" \
    -e "s/{{ current_version }}/${vmVirtIOCurrenetVersion}/g" \
    -e "s/{{ available_version }}/${vmVirtIOLatestVersion}/g" \
    -e "s/{{ release_date }}/${releaseDate}/g" \
    "${SVG_IMAGE_PATH}/update-${vmid}.svg" > "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" && \
    mv "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
}

# @function build_svg_qemu_ga_update_nag
# @description Generates SVG banner showing QEMU Guest Agent update availability only
# @args vmid (string): Proxmox VM ID
#       vmQEMUGACurrenetVersion (string): Currently installed QEMU GA version
#       vmQEMUGALatestVersion (string): Latest available QEMU GA version
#       releaseDate (string): QEMU GA release date (YYYY-MM-DD)
# @returns 0 on success, 1 on file operation error
# @example
#   build_svg_qemu_ga_update_nag 100 9.0.0 9.1.0 2025-01-20
function build_svg_qemu_ga_update_nag() {
    local vmid=$1
    local vmQEMUGACurrenetVersion=$2
    local vmQEMUGALatestVersion=$3
    local releaseDate=$4

    cp "${SVG_IMAGE_TEMPLATE}" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
    sed -e "s/{{ title }}/QEMU Guest Agent Update Available/g" \
    -e "s/{{ current_version }}/${vmQEMUGACurrenetVersion}/g" \
    -e "s/{{ available_version }}/${vmQEMUGALatestVersion}/g" \
    -e "s/{{ release_date }}/${releaseDate}/g" \
    "${SVG_IMAGE_PATH}/update-${vmid}.svg" > "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" && \
    mv "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
}

# @function maybe_show_update_nag
# @description Orchestrates SVG nag creation, VM description updates, and state persistence based on update availability
# @args node (string): Proxmox node name
#       vmid (string): Proxmox VM ID
#       need_virtio (bool): true if VirtIO update is available
#       need_qemu_ga (bool): true if QEMU GA update is available
#       virtio_ver (string): Current VirtIO version
#       current_virtio (string): Latest available VirtIO version
#       qemu_ver (string): Current QEMU GA version
#       current_qemu (string): Latest available QEMU GA version
#       current_virtio_rel (string): VirtIO release date
#       current_qemu_rel (string): QEMU GA release date
#       vmgenid (string): VM generation ID for clone detection
# @returns 0 on success; creates SVG banners and updates VM description
# @example
#   maybe_show_update_nag "$node" 100 true false "0.1.283" "0.1.285" "9.0.0" "9.0.0" "2024-12-01" "2024-11-01" "$vmgenid"
maybe_show_update_nag() {
  local node="$1" vmid="$2"
  local need_virtio="$3" need_qemu_ga="$4"
  local virtio_ver="$5" current_virtio="$6"
  local qemu_ver="$7" current_qemu="$8"
  local current_virtio_rel="$9" current_qemu_rel="${10}"
  local vmgenid="${11}"

  if [[ "$need_virtio" == true && "$need_qemu_ga" == true ]]; then
    build_svg_update_nag \
      "$vmid" \
      "$virtio_ver" "$current_virtio" \
      "$qemu_ver" "$current_qemu" \
      "$current_virtio_rel" "$current_qemu_rel"

    update_vm_description_with_update_nag "$node" "$vmid" "$need_virtio" "$need_qemu_ga"
    save_vm_state "$vmid" "$virtio_ver" "$qemu_ver" "true" "$vmgenid"

  elif [[ "$need_virtio" == true ]]; then
    build_svg_virtio_update_nag \
      "$vmid" \
      "$virtio_ver" "$current_virtio" "$current_virtio_rel"

    update_vm_description_with_update_nag "$node" "$vmid" "$need_virtio" "$need_qemu_ga"
    save_vm_state "$vmid" "$virtio_ver" "$qemu_ver" "true" "$vmgenid"

  elif [[ "$need_qemu_ga" == true ]]; then
    build_svg_qemu_ga_update_nag \
      "$vmid" \
      "$qemu_ver" "$current_qemu" "$current_qemu_rel"

    update_vm_description_with_update_nag "$node" "$vmid" "$need_virtio" "$need_qemu_ga"
    save_vm_state "$vmid" "$virtio_ver" "$qemu_ver" "true" "$vmgenid"

  else
    # Defensive: nag_status=0 but no updates are needed
    log_warn "nag_status=0 but neither VirtIO nor QEMU GA update is needed for VM $vmid; saving state without nag."
    save_vm_state "$vmid" "$virtio_ver" "$qemu_ver" "false" "$vmgenid"
  fi
}