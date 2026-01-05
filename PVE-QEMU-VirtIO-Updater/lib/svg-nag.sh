#!/bin/env bash

SVG_IMAGE_PATH="/usr/share/pve-manager/images/"
SVG_IMAGE_TEMPLATE="${SCRIPT_DIR}/templates/svg/virtio-template.svg"

function build_svg_virtio_update_nag() {
    local vmid=$1
    local vmVirtIOCurrenetVersion=$2
    local vmVirtIOLatestVersion=$3
    local releaseDate=$4

    cp "${SVG_IMAGE_TEMPLATE}" "${SVG_IMAGE_PATH}/virtio-${vmid}.svg"
    sed -e "s/0\.1\.240/${vmVirtIOCurrenetVersion}/g" \
    -e "s/0\.1\.262/${vmVirtIOLatestVersion}/g" \
    -e "s/2026-01-15/${releaseDate}/g" \
    "${SVG_IMAGE_PATH}/virtio-${vmid}.svg" > "${SVG_IMAGE_PATH}/virtio-${vmid}.svg"

}