#!/usr/bin/env bash
#
# Module: default.sh (PVE-QEMU-VirtIO-Updater)
# Description: Core functions for version fetching, dependency checking, and update notification logic
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: curl, jq, sed, awk
# Environment: N/A (functions exported for use by main.sh)
# Usage: source lib/default.sh
#
# Functions:
#   - check_script_dependencies: Verify required tools are installed
#   - fetch_latest_virtio_version: Fetch latest VirtIO driver version from Fedora Archive
#   - fetch_latest_qemu_ga_version: Fetch latest QEMU Guest Agent version from Fedora Archive
#   - maybe_show_update_nag: Determine and display update notification if needed

# @function check_script_dependencies
# @description Validates that all required external tools are installed and available in PATH
# @args None
# @returns 0 if all dependencies found, 1 if any missing; logs result
# @example
#   check_script_dependencies
function check_script_dependencies() {
    local dependencies=( "curl" "jq" "pvesh" "qm" "grep" "sed" "awk" "sort")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_fatal "Error: $dep is not installed."
            return 1
        fi
    done
    log_info "All script dependencies are installed."
    return 0
}

# @function fetch_latest_virtio_version
# @description Fetches the latest available VirtIO driver version from Fedora People Archive
# @args None
# @returns JSON object with keys: version (e.g., "0.1.285"), release (date string, e.g., "2025-01-15")
# @example
#   version_json=$(fetch_latest_virtio_version)
#   latest_ver=$(echo "$version_json" | jq -r '.version')
fetch_latest_virtio_version() {
    local FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/"

    # Use curl and capture status code
    local archive_page
    archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || {
        log_error "Failed to fetch Fedora People Archive page"
    }

    local http_code=$(echo "$archive_page" | tail -n1)
    # Use sed to remove the last line (the http code)
    local page_content=$(echo "$archive_page" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
    fi

    # Refactored AWK to be compatible with mawk and gawk
    latest_json=$(echo "$page_content" | awk '
        /virtio-win-[0-9.]+-([0-9]+)\// {
            # Find the version string
            start = match($0, /virtio-win-[0-9.]+-([0-9]+)\//)
            if (start > 0) {
                # Extract full match like virtio-win-0.1.285-1/
                full_match = substr($0, RSTART, RLENGTH)
                # Strip prefix and suffix to get 0.1.285-1
                gsub(/virtio-win-|\//, "", full_match)
                # Split at hyphen to remove the release number (the -1)
                split(full_match, parts, "-")
                version = parts[1]

                # Find the date
                if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                    date = substr($0, RSTART, RLENGTH)
                    print version " " date
                }
            }
        }' |
        sort -V |
        tail -n1 |
        awk '{ver=$1; $1=""; sub(/^ /, "", $0); printf("{\"version\":\"%s\",\"release\":\"%s\"}\n", ver, $0)}'
    )

    if [ -z "$latest_json" ]; then
        log_error "Could not find any virtio-win directory versions"
    fi

    echo "$latest_json"
}

# @function fetch_latest_qemu_ga_version
# @description Fetches the latest available QEMU Guest Agent version from Fedora People Archive
# @args None
# @returns JSON object with keys: version (e.g., "9.1.0"), release (date string, e.g., "2025-01-20")
# @example
#   qemu_json=$(fetch_latest_qemu_ga_version)
#   latest_qemu=$(echo "$qemu_json" | jq -r '.version')
fetch_latest_qemu_ga_version() {
    local FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-qemu-ga/"

    # Abruf der Seite und des HTTP-Statuscodes
    local archive_page
    archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || {
        log_error "Failed to fetch Fedora People Archive page"
    }

    local http_code=$(echo "$archive_page" | tail -n1)
    # Entferne die letzte Zeile (den Statuscode) sicher mit sed
    local page_content=$(echo "$archive_page" | sed '$d')

    if [ "$http_code" != "200" ]; then
        log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
    fi

    # Extraktion der Version und des Datums
    latest_json=$(echo "$page_content" | awk '
        /qemu-ga-win-[^"]+\// {
            # Suche nach dem Versions-String (z.B. qemu-ga-win-9.1.0)
            if (match($0, /qemu-ga-win-[0-9]+\.[0-9]+\.[0-9]+/)) {
                full_match = substr($0, RSTART, RLENGTH)
                # Entferne den Präfix, um nur die Version zu behalten
                sub(/qemu-ga-win-/, "", full_match)
                version = full_match

                # Suche nach dem Datum (YYYY-MM-DD)
                if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
                    date = substr($0, RSTART, RLENGTH)
                    print version " " date
                }
            }
        }' |
        sort -V |
        tail -n1 |
        awk '{ver=$1; $1=""; sub(/^ /, "", $0); printf("{\"version\":\"%s\",\"release\":\"%s\"}\n", ver, $0)}'
    )

    if [ -z "$latest_json" ]; then
        log_error "Could not find any qemu-ga-win directory versions"
    fi

    echo "$latest_json"
}