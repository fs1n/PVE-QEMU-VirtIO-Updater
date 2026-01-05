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
              # z.B.: ... virtio-win-0.1.285-1/ ... 2025-09-15 17:26 ...
              match($0, /virtio-win-([0-9.]+-[0-9]+)/, m)
              if (m[1] != "") {
                  version = m[1]   # 0.1.285-1
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