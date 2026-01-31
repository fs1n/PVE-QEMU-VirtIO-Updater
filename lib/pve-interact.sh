#!/usr/bin/env bash
#
# Module: pve-interact.sh (PVE-QEMU-VirtIO-Updater)
# Description: Proxmox VE API wrapper functions for VM discovery, version querying, and description updates
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: pvesh, qm, jq, grep
# Environment: N/A (functions exported for use by main.sh)
# Usage: source lib/pve-interact.sh
#
# Functions:
#   - get_windows_vms: Query all Windows VMs across Proxmox cluster
#   - get_windows_virtio_version: Query VirtIO driver version inside Windows VM via QEMU Guest Agent
#   - get_windows_QEMU_GA_version: Query QEMU Guest Agent version inside Windows VM
#   - update_vm_description_with_update_nag: Add SVG update banner to VM description
#   - remove_vm_nag: Remove update nag banner from VM description
#   - get_vm_creation_date: Extract VM creation date from Proxmox metadata

# @function get_windows_vms
# @description Discovers all Windows VMs running on the Proxmox cluster and returns their metadata as JSON
# @args None
# @returns JSON object with VM IDs as keys; exits 0 on success (even if no VMs found)
# @example
#   windows_vms=$(get_windows_vms)
#   echo "$windows_vms" | jq '.'
function get_windows_vms() {
    # Initialize an empty JSON object
    local json_items=""
    # Local variables to avoid leaking state outside this function
    local nodes node vms vmid vm_config os_type vm_name status vmgenid vmgenid_json vm_obj json_output

    # List all nodes in the cluster
    nodes=$(pvesh get /nodes --output-format json | jq -r '.[].node')
    if [ -z "$nodes" ]; then
        # Ensure stdout remains valid JSON; send status to stderr
        echo '{}'
        log_error "No nodes found."
        return 1
    fi
    for node in $nodes; do
        # List all QEMU VMs on this node
        vms=$(pvesh get /nodes/$node/qemu --output-format json | jq -r '.[].vmid')
        if [ -z "$vms" ]; then
            echo "No VMs found on node $node." >&2
            continue
        fi

        for vmid in $vms; do
            # Get VM configuration
            vm_config=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format json)

            # Check if the OS type is 'win' (Windows)
            os_type=$(echo "$vm_config" | jq -r '.ostype // empty')
            if [[ "$os_type" == w* ]]; then
                # Matches: wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11 -> Well documented in the PVE API docs (https://pve.proxmox.com/pve-docs/api-viewer/index.html#/nodes/{node}/qemu/{vmid}/config -> ctrl+f "ostype") available ostypes are documented there.
                vm_name=$(echo "$vm_config" | jq -r '.name // empty')
                status=$(pvesh get /nodes/$node/qemu/$vmid/status/current --output-format json | jq -r '.status')
                vmgenid=$(echo "$vm_config" | jq -r '.vmgenid // empty')
                if [ -z "$vmgenid" ]; then
                    vmgenid_json=null
                else
                    vmgenid_json="\"$vmgenid\""
                fi

                # Build a per-VM JSON object safely using jq
                vm_obj=$(jq -n \
                    --arg node "$node" \
                    --arg name "$vm_name" \
                    --arg ostype "$os_type" \
                    --arg status "$status" \
                    --arg vmid "$vmid" \
                    --argjson vmgenid "$vmgenid_json" \
                    '{($vmid): {node: $node, name: $name, ostype: $ostype, status: $status, vmgenid: $vmgenid}}')

                # Accumulate objects (one per line)
                json_items+="$vm_obj"$'\n'
            fi
        done
    done

    # Merge accumulated objects or return an empty object
    if [ -n "$json_items" ]; then
        json_output=$(jq -s 'add' <<< "$json_items")
    else
        json_output='{}'
    fi

    echo "$json_output"
}

# @function get_windows_virtio_version
# @description Query VirtIO driver version installed in a Windows VM via QEMU Guest Agent
# @args vmid (string): Proxmox VM ID
# @returns String containing version (e.g., "0.1.283"), empty string if not found or error
# @example
#   virtio_ver=$(get_windows_virtio_version 100)
function get_windows_virtio_version() {
    local vmid=$1
    # Use guest-agent to get the VirtIO driver version inside the Windows VM
    version=$(qm guest exec $vmid -- powershell.exe -Command 'Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName } | Where-Object { $_.DisplayName -like "*virtio*installer*" } | Select-Object -ExpandProperty DisplayVersion' 2>/dev/null | jq -r '.["out-data"]' | tr -d '\r\n')
    echo "$version"
}

# @function get_windows_QEMU_GA_version
# @description Query QEMU Guest Agent version installed in a Windows VM
# @args vmid (string): Proxmox VM ID
# @returns String containing version (e.g., "9.1.0"), empty string if not found or error
# @example
#   qemu_ver=$(get_windows_QEMU_GA_version 100)
function get_windows_QEMU_GA_version() {
    local vmid=$1
    # Use guest-agent to get the QEMU Guest Agent driver version inside the Windows VM
    version=$(qm guest exec $vmid -- powershell.exe -Command "\$qemuPaths = @('C:\\Program Files\\Qemu-ga\\qemu-ga.exe', 'C:\\Program Files (x86)\\Qemu-ga\\qemu-ga.exe'); foreach (\$path in \$qemuPaths) { if (Test-Path \$path) { (Get-Item \$path).VersionInfo.FileVersion } }" 2>/dev/null | jq -r '.["out-data"]' | tr -d '\r\n')
    echo "$version"
}

# @function update_vm_description_with_update_nag
# @description Adds SVG update banner to Proxmox VM description, preserving existing content
# @args node (string): Proxmox node name
#       vmid (string): Proxmox VM ID
#       need_virtio (bool): true if VirtIO update is available
#       need_qemu_ga (bool): true if QEMU GA update is available
# @returns 0 on success, 1 on error; modifies VM description via qm set
# @example
#   update_vm_description_with_update_nag "$node" 100 true false
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
        if echo "$current_description" | grep -q "update-$vmid\.svg"; then
            echo "Update banner already present in VM $vmid"
            return 0
        fi
        
        # Prepend banner to existing description with separator
        new_description="${update_banner}<hr/>${current_description}"
    fi
    
    # Update the description (escape quotes properly)
    qm set "$vmid" -description "$new_description"
    
    log_info "Updated description for VM $vmid with VirtIO update nag."
}

# @function remove_vm_nag
# @description Removes the SVG update banner from VM description, preserving other content
# @args node (string): Proxmox node name
#       vmid (string): Proxmox VM ID
# @returns 0 on success; modifies VM description via qm set
# @example
#   remove_vm_nag "$node" 100
function remove_vm_nag() {
    local node=$1
    local vmid=$2
    
    local current_vm_config=$(pvesh get /nodes/$node/qemu/$vmid/config --output-format json)
    local current_description=$(echo "$current_vm_config" | jq -r '.description // empty')
    
    # Check if nag exists in description
    if [[ -z "$current_description" ]] || ! echo "$current_description" | grep -q "update-$vmid.svg"; then
        log_debug "No update nag found for VM $vmid"
        return 0
    fi
    
    # Remove the nag banner and separator
    local new_description=$(echo "$current_description" | sed -E "s|<img src=\"/pve2/images/update-$vmid\.svg\"[^>]*/>(<hr/>)?||g")
    
    # Clean up any leftover empty lines or double separators
    new_description=$(echo "$new_description" | sed -E 's|<hr/>(<hr/>)+|<hr/>|g' | sed -E 's|^<hr/>||' | sed -E 's|<hr/>$||')
    
    # Update VM description
    if [[ -n "$new_description" && "$new_description" != "null" ]]; then
        qm set "$vmid" -description "$new_description"
    else
        # Description is now empty, clear it
        qm set "$vmid" -description ""
    fi
    
    log_info "Removed update nag from VM $vmid"
}

# @function get_vm_creation_date
# @description Extract VM creation date/time from Proxmox metadata
# @args node (string): Proxmox node name
#       vmid (string): Proxmox VM ID
# @returns Creation date in format "YYYY-MM-DD HH:MM:SS", or "unknown" if not available
# @example
#   created=$(get_vm_creation_date "$node" 100)
function get_vm_creation_date() {
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