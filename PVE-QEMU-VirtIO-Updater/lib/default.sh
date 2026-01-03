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

function fetch_latest_virtio_msi() {
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

        # Construct URL to latest directory
        latest_url="${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}virtio-win-${latest_version}/"
        log_info "Accessing latest virtio-win directory at ${latest_url}"
        # Fetch latest directory listing
        latest_page=$(curl -sS -w "\n%{http_code}" "${latest_url}") || log_error "Failed to fetch latest directory"
        http_code=$(echo "$latest_page" | tail -n1)
        page_content=$(echo "$latest_page" | head -n-1)

        if [ "$http_code" != "200" ]; then
            log_error "Failed to access latest directory. HTTP Status: ${http_code}"
        fi

        log_info "Successfully accessed latest virtio-win directory"

        # Check if MSI file exists
        if ! echo "$page_content" | grep -q "href=\"${MSI_FILENAME}\""; then
            log_error "Could not find ${MSI_FILENAME} in the latest directory"
        fi

        # Construct download URL
        download_url="${latest_url}${MSI_FILENAME}"
        log_info "Download URL: ${download_url}"

        # Download file
        output_path="${SCRIPT_ROOT}/${MSI_FILENAME}"
        log_info "Starting download to: ${output_path}"
        if curl -fSL --progress-bar -o "$output_path" "$download_url"; then
            log_info "Successfully downloaded ${MSI_FILENAME}"
            log_info "File saved to: ${output_path}"

            # Optional: Verify file size
            file_size=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path" 2>/dev/null)
            log_info "Downloaded file size: ${file_size} bytes"
        else
            log_error "Failed to download ${MSI_FILENAME}"
        fi

        exit 0
}