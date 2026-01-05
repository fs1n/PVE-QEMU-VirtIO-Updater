#!/bin/env bash

SVG_IMAGE_PATH="/usr/share/pve-manager/images/"
SVG_IMAGE_TEMPLATE="${SCRIPT_DIR}/templates/svg/update-nag-template.svg"

function build_svg_update_nag() {
    local vmid=$1
    local vmVirtIOCurrenetVersion=$2
    local vmVirtIOLatestVersion=$3
    local vmQEMUGACurrenetVersion=$4
    local vmQEMUGALatestVersion=$5
    local releaseDate=$6

    cp "${SVG_IMAGE_TEMPLATE}" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
    
    # Build the update info string
    local update_info="VirtIO: ${vmVirtIOCurrenetVersion} → ${vmVirtIOLatestVersion} | QEMU GA: ${vmQEMUGACurrenetVersion} → ${vmQEMUGALatestVersion}"
    
    sed -e "s/{{ title }}/System Updates Available/g" \
    -e "s/{{ current_version }}/${vmVirtIOCurrenetVersion}/g" \
    -e "s/{{ available_version }}/${vmVirtIOLatestVersion}/g" \
    -e "s/{{ qemu_ga_current_version }}/${vmQEMUGACurrenetVersion}/g" \
    -e "s/{{ qemu_ga_available_version }}/${vmQEMUGALatestVersion}/g" \
    -e "s/{{ release_date }}/${releaseDate}/g" \
    -e "s/{{ update_info }}/${update_info}/g" \
    "${SVG_IMAGE_PATH}/update-${vmid}.svg" > "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" && \
    mv "${SVG_IMAGE_PATH}/update-${vmid}.svg.tmp" "${SVG_IMAGE_PATH}/update-${vmid}.svg"
}

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