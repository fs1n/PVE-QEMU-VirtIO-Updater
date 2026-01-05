function get_windows_vms() {
    # Initialize an empty JSON object
    json_output="{"

    # List all nodes in the cluster
    nodes=$(pvesh get /nodes --output-format json | jq -r '.[].node')
    if [ -z "$nodes" ]; then
        echo "No nodes found."
        return 1
    fi
    for node in $nodes; do
      # List all QEMU VMs on this node
      vms=$(pvesh get /nodes/$node/qemu --output-format json | jq -r '.[].vmid')
      if [ -z "$vms" ]; then
          echo "No VMs found on node $node."
          continue
      fi
    done
    for vmid in $vms; do
        # Get VM configuration
        vm_config=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format json)
        
        # Check if the OS type is 'win' (Windows)
        os_type=$(echo "$vm_config" | jq -r '.ostype // empty')
        if [[ "$os_type" == w* ]]; then
            # Matches: wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11 -> Well documented in the PVE API docs (https://pve.proxmox.com/pve-docs/api-viewer/index.html#/nodes/{node}/qemu/{vmid}/config -> ctrl+f "ostype") available ostypes are documented there.
            vm_name=$(echo "$vm_config" | jq -r '.name // empty')
            json_output+="\"$vmid\": {\"node\": \"$node\", \"name\": \"$vm_name\", \"ostype\": \"$os_type\"},"
        fi
    done
    # Remove trailing comma and close JSON object
    json_output="${json_output%,}}"
    
    echo "$json_output"
}

function get_windows_virtio_version() {
    local vmid=$1
    # Use guest-agent to get the VirtIO driver version inside the Windows VM
    version=$(qm guest exec $vmid --cmd "powershell -Command \"(Get-WmiObject Win32_PnPSignedDriver | Where-Object { \$_.DeviceName -like '*VirtIO*' } | Select-Object -First 1).DriverVersion\"" 2>/dev/null | tr -d '\r')
    echo "$version"
}

function get_windows_QEMU_GA_version() {
    local vmid=$1
    # Use guest-agent to get the QEMU Guest Agent driver version inside the Windows VM
    version=$(qm guest exec $vmid -- powershell.exe -Command "\$qemuPaths = @('C:\\Program Files\\Qemu-ga\\qemu-ga.exe', 'C:\\Program Files (x86)\\Qemu-ga\\qemu-ga.exe'); foreach (\$path in \$qemuPaths) { if (Test-Path \$path) { (Get-Item \$path).VersionInfo.FileVersion } }" 2>/dev/null | jq -r '.["out-data"]' | tr -d '\r\n')
    echo "$version"
}

function update_vm_description_with_update_nag() {
    local node=$1
    local vmid=$2
    local need_virtio="$3"
    local need_qemu_ga="$4"
    
    current_vm_config=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format json)
    
    current_description=$(echo "$current_vm_config" | jq -r '.description // empty')
    
    update_banner='<img src="/pve2/images/update-'$vmid'.svg" alt="VirtIO Update" />'
    
    # Check if description exists and is not empty
    if [ -z "$current_description" ] || [ "$current_description" = "null" ]; then
        # No existing description, just set the banner
        new_description="$update_banner"
    else
        # Check if banner already exists to avoid duplicates
        if echo "$current_description" | grep -q "virtio-update"; then
            echo "Update banner already present in VM $vmid"
            return 0
        fi
        
        # Prepend banner to existing description with separator
        new_description="${update_banner}<hr/>${current_description}"
    fi
    
    # Update the description (escape quotes properly)
    qm set $vmid -description "$new_description"
    
    log_info "Updated description for VM $vmid with VirtIO update nag."
}


get_vm_creation_date() {
    local node=$1
    local vmid=$2
    
    local ctime=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format json | \
        jq -r '.meta // empty' | \
        grep -oP 'ctime=\K[0-9]+')
    
    if [ -n "$ctime" ]; then
        date -d "@$ctime" '+%Y-%m-%d %H:%M:%S'
    else
        echo "unknown"
    fi
}