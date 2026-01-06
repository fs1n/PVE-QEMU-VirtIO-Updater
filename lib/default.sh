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

fetch_latest_virtio_version() {
    local FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/"

    archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || \
        log_error "Failed to fetch Fedora People Archive page"

    http_code=$(echo "$archive_page" | tail -n1)
    page_content=$(echo "$archive_page" | head -n-1)

    if [ "$http_code" != "200" ]; then
        log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
    fi

    latest_json=$(echo "$page_content" |
        awk '
          /virtio-win-[0-9.]+-[0-9]+/ {
              # e.g.: ... virtio-win-0.1.285-1/ ... 2025-09-15 17:26 ...
              # capture only 0.1.285 (without the -1)
              match($0, /virtio-win-([0-9.]+)-[0-9]+\//, m)
              if (m[1] != "") {
                  version = m[1]   # 0.1.285
                  match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/, d)
                  if (d[0] != "") {
                      date = d[0]
                      print version " " date
                  }
              }
          }
        ' |
        sort -V |
        tail -n1 |
        awk '{ver=$1; $1=""; sub(/^ /, "", $0); printf("{\"version\":\"%s\",\"release\":\"%s\"}\n", ver, $0)}'
    )


    if [ -z "$latest_json" ]; then
        log_error "Could not find any virtio-win directory versions"
    fi

    echo "$latest_json"
}

fetch_latest_qemu_ga_version() {
    local FEDORA_PEOPLE_ARCHIVE_ROOT_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-qemu-ga/"

    archive_page=$(curl -sS -w "\n%{http_code}" "${FEDORA_PEOPLE_ARCHIVE_ROOT_URL}") || \
        log_error "Failed to fetch Fedora People Archive page"

    http_code=$(echo "$archive_page" | tail -n1)
    page_content=$(echo "$archive_page" | head -n-1)

    if [ "$http_code" != "200" ]; then
        log_error "Failed to access Fedora People Archive. HTTP Status: ${http_code}"
    fi

    latest_json=$(echo "$page_content" |
        awk '
          /qemu-ga-win-[^"]+\// {
          	  match($0, /qemu-ga-win-([0-9]+\.[0-9]+\.[0-9]+)/, m)
	  		  if (m[1] != "") {
 			      version = m[1]
                  match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/, d)
                  if (d[0] != "") {
                      date = d[0]
                      print version " " date
                  }
              }
          }
        ' |
        sort -V |
        tail -n1 |
        awk '{ver=$1; $1=""; sub(/^ /, "", $0); printf("{\"version\":\"%s\",\"release\":\"%s\"}\n", ver, $0)}'
    )

    if [ -z "$latest_json" ]; then
        log_error "Could not find any qemu-ga-win directory versions"
    fi

    echo "$latest_json"
}

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
