#!/bin/env bash

function check_script_dependencies() {
    local dependencies=( "curl" "jq")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_fatal "Error: $dep is not installed."
            return 1
        fi
    done
    log_info "All script dependencies are installed."
    return 0
}

function fetch_latest_virtio_version() {
        readonly FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/"
        readonly MSI_FILENAME="virtio-win-gt-x64.msi"

        archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || log_error "Failed to fetch Fedora People Archive page"

        # Extract HTTP status code (last line)
        http_code=$(echo "$archive_page" | tail -n1)
        page_content=$(echo "$archive_page" | head -n-1)

        if [ "$http_code" != "200" ]; then
            log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
        fi

        log_info "Successfully accessed Fedora People Archive"

        # Extract and parse directory links
        log_info "Parsing directory links for virtio-win versions"
        latest_version=$(echo "$page_content" | \
            grep -oP 'href="virtio-win-[\d\.]+-\d+/"' | \
            sed 's/href="virtio-win-//;s/\/"$//' | \
            sort -V | \
            tail -n1)

        if [ -z "$latest_version" ]; then
            log_error "Could not find any virtio-win directory versions"
        fi

        log_info "Latest version found: ${latest_version}"

        echo "$latest_version"
}

function fetch_latest_qemu_ga_version() {
        readonly FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-qemu-ga/"
        readonly MSI_FILENAME="qemu-ga-x86_64.msi"

        archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || log_error "Failed to fetch Fedora People Archive page"

        # Extract HTTP status code (last line)
        http_code=$(echo "$archive_page" | tail -n1)
        page_content=$(echo "$archive_page" | head -n-1)

        if [ "$http_code" != "200" ]; then
            log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
        fi

        log_info "Successfully accessed Fedora People Archive"

        # Extract and parse directory links
        log_info "Parsing directory links for qemu-ga-win versions"
        latest_version=$(echo "$page_content" | \
            grep -oP 'href="qemu-ga-win-[^"]+/"' | \
            sed 's/href="qemu-ga-win-//;s/\/"$//' | \
            sort -V | \
            tail -n1)

        if [ -z "$latest_version" ]; then
            log_error "Could not find any qemu-ga-win directory versions"
        fi

        log_info "Latest version found: ${latest_version}"

        echo "$latest_version"
}