#!/bin/env bash
# State management for VM update tracking

STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.state}"

# Ensure state directory exists
init_state_dir() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR"
        log_debug "Created state directory: $STATE_DIR"
    fi
}

# Save current VM state after checking versions
save_vm_state() {
    local vmid=$1
    local virtio_ver=$2
    local qemu_ga_ver=$3
    local nag_shown=$4  # true/false
    
    local state_file="$STATE_DIR/vm-${vmid}.state"
    
    cat > "$state_file" <<EOF
# Auto-generated state file for VM $vmid
LAST_CHECKED=$(date +%s)
LAST_CHECKED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
VIRTIO_VERSION="$virtio_ver"
QEMU_GA_VERSION="$qemu_ga_ver"
NAG_ACTIVE=$nag_shown
EOF
    
    log_debug "Saved state for VM $vmid: VirtIO=$virtio_ver, QEMU-GA=$qemu_ga_ver, Nag=$nag_shown"
}

# Load VM state from file
load_vm_state() {
    local vmid=$1
    local state_file="$STATE_DIR/vm-${vmid}.state"
    
    if [[ ! -f "$state_file" ]]; then
        return 1  # No state file exists
        log_debug "No state file for VM $vmid"
    fi
    
    # Source the state file to load variables
    source "$state_file"
    
    # Export variables so caller can access them
    export STORED_VIRTIO_VERSION="$VIRTIO_VERSION"
    export STORED_QEMU_GA_VERSION="$QEMU_GA_VERSION"
    export STORED_NAG_ACTIVE="$NAG_ACTIVE"
    export STORED_LAST_CHECKED="$LAST_CHECKED"
    
    return 0
}

# Check if nag should be displayed for this VM
should_show_nag() {
    local vmid=$1
    local current_virtio=$2
    local latest_virtio=$3
    local current_qemu_ga=$4
    local latest_qemu_ga=$5
    
    # Load previous state
    if ! load_vm_state "$vmid"; then
        # No state exists, this is first run
        log_debug "No state for VM $vmid, will check for updates"
        return 0  # Show nag if updates available
    fi
    
    # Check if VM is already up to date
    local virtio_uptodate=false
    local qemu_ga_uptodate=false
    
    if [[ "$current_virtio" == "$latest_virtio" ]]; then
        virtio_uptodate=true
    fi
    
    if [[ "$current_qemu_ga" == "$latest_qemu_ga" ]]; then
        qemu_ga_uptodate=true
    fi
    
    # If both are up to date, no nag needed
    if [[ "$virtio_uptodate" == true && "$qemu_ga_uptodate" == true ]]; then
        log_debug "VM $vmid is up to date (VirtIO: $current_virtio, QEMU-GA: $current_qemu_ga)"
        
        # If nag was previously active, remove it
        if [[ "$STORED_NAG_ACTIVE" == "true" ]]; then
            log_info "VM $vmid is now up to date, removing update nag"
            return 2  # Special code: remove existing nag
        fi
        
        return 1  # No nag needed
    fi
    
    # Check if versions changed since last check (new update available)
    if [[ "$STORED_VIRTIO_VERSION" != "$current_virtio" ]] || \
       [[ "$STORED_QEMU_GA_VERSION" != "$current_qemu_ga" ]]; then
        log_debug "VM $vmid versions changed since last check, showing nag"
        return 0  # Show nag
    fi
    
    # Same versions as before and nag already shown
    if [[ "$STORED_NAG_ACTIVE" == "true" ]]; then
        log_debug "VM $vmid nag already active, no action needed"
        return 1  # Nag already shown, don't duplicate
    fi
    
    # Default: show nag if updates available
    return 0
}

# Remove update nag from VM description
remove_vm_nag() {
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
        qm set $vmid -description "$new_description"
    else
        # Description is now empty, clear it
        qm set $vmid -description ""
    fi
    
    log_info "Removed update nag from VM $vmid"
    
    # Update state to reflect nag removal
    save_vm_state "$vmid" "$current_virtio" "$current_qemu_ga" "false"
}

# Clean up state files for VMs that no longer exist
cleanup_stale_state_files() {
    local active_vmids=$1  # JSON object with VM IDs as keys
    
    if [[ ! -d "$STATE_DIR" ]]; then
        return 0
    fi
    
    for state_file in "$STATE_DIR"/vm-*.state; do
        if [[ ! -f "$state_file" ]]; then
            continue
        fi
        
        # Extract VMID from filename
        local vmid=$(basename "$state_file" | sed -E 's/vm-([0-9]+)\.state/\1/')
        
        # Check if VM still exists
        if ! echo "$active_vmids" | jq -e ".\"$vmid\"" > /dev/null 2>&1; then
            log_info "Removing stale state file for non-existent VM $vmid"
            rm -f "$state_file"
        fi
    done
}
