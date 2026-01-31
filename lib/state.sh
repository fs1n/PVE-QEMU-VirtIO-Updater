#!/usr/bin/env bash
#
# Module: state.sh (PVE-QEMU-VirtIO-Updater)
# Description: VM state management for tracking update status, version history, and VM identity across runs
# Author: Frederik S. (fs1n) and PVE-QEMU-VirtIO-Updater Contributors
# Date: 2025-01-31
#
# Dependencies: grep, sed, jq
# Environment: STATE_DIR, SCRIPT_DIR
# Usage: source lib/state.sh; init_state_dir; save_vm_state vmid version1 version2 nag_shown vmgenid
#
# Functions:
#   - init_state_dir: Create state directory if needed
#   - get_vm_genid: Retrieve or derive unique VM generation ID for clone detection
#   - save_vm_state: Persist VM update state to file
#   - load_vm_state: Load VM state from file and export as environment variables
#   - should_show_nag: Determine if update notification should be displayed
#   - cleanup_stale_state_files: Remove state files for VMs that no longer exist

# State management for VM update tracking

STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/.state}"

# @function init_state_dir
# @description Creates the state directory if it does not exist; called once at startup
# @args None
# @returns 0 on success, 1 if directory creation failed
# @example
#   init_state_dir
# Ensure state directory exists (called once at startup in main.sh)
function init_state_dir() {
    if [[ ! -d "$STATE_DIR" ]]; then
        if ! mkdir -p "$STATE_DIR"; then  
            log_error "Failed to create state directory: $STATE_DIR"  
            return 1  
        fi
        log_debug "Created state directory: $STATE_DIR"
    fi
    return 0
}

# @function get_vm_genid
# @description Retrieve VM generation ID for clone detection; falls back to ctime+name if vmgenid not set
# @args node (string): Proxmox node name
#       vmid (string): Proxmox VM ID
# @returns VM generation ID (UUID or fallback string)
# @example
#   vmgenid=$(get_vm_genid "$node" 100)
# Get VM Generation ID (unique identifier that changes on clone/restore)
function get_vm_genid() {
    local node=$1
    local vmid=$2
    
    local vmgenid
    # Prefer vmgenid from windows_vms; if missing/null, fall back to an identifier derived from vm_config (ctime+name)
    # windows_vms is expected to be a global variable containing the JSON of all Windows VMs -> Created in main.sh
    vmgenid=$(echo "$windows_vms" | jq -r --arg vmid "$vmid" '.[$vmid].vmgenid // empty') 
    
    if [[ -z "$vmgenid" || "$vmgenid" == "null" ]]; then
        # Fallback: if vmgenid not set, fetch VM config and use ctime+name  
        local vm_config  
        vm_config=$(pvesh get "/nodes/${node}/qemu/${vmid}/config" --output-format json 2>/dev/null || echo '{}')  
        local ctime  
        ctime=$(echo "$vm_config" | jq -r '.meta // empty' | grep -oP 'ctime=\K[0-9]+' || echo "0")  
        local vm_name  
        vm_name=$(echo "$vm_config" | jq -r '.name // "unnamed"')  
        echo "fallback-${ctime}-${vm_name}"
        log_warn "VM $vmid has no vmgenid, using fallback identifier" >&2
    else
        echo "$vmgenid"
    fi
}

# @function save_vm_state
# @description Persist current VM version and nag state to a state file for future comparisons
# @args vmid (string): Proxmox VM ID
#       virtio_ver (string): Current VirtIO version
#       qemu_ga_ver (string): Current QEMU GA version
#       nag_shown (bool): Whether nag is currently active
#       vmgenid (string): VM generation ID
# @returns 0 on success, 1 if file write failed
# @example
#   save_vm_state 100 "0.1.283" "9.0.0" "true" "$vmgenid"
# Save current VM state with identity tracking
function save_vm_state() {
    local vmid=$1
    local virtio_ver=$2
    local qemu_ga_ver=$3
    local nag_shown=$4
    local vmgenid=$5

    local state_file="$STATE_DIR/vm-${vmid}.state"

    {
        cat > "$state_file" <<EOF
# Auto-generated state file for VM $vmid
VMGENID="$vmgenid"
LAST_CHECKED=$(date +%s)
LAST_CHECKED_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
VIRTIO_VERSION="$virtio_ver"
QEMU_GA_VERSION="$qemu_ga_ver"
NAG_ACTIVE=$nag_shown
EOF
    } || {
        log_error "Failed to save state for VM $vmid to '$state_file' (disk full? permissions?)"
        return 1
    }

    log_debug "Saved state for VM $vmid to '$state_file'"
}

# @function load_vm_state
# @description Load VM state from file and export as environment variables (STORED_VMGENID, STORED_VIRTIO_VERSION, etc.)
# @args vmid (string): Proxmox VM ID
# @returns 0 on success (state found), 1 if state file not found; exports STORED_* variables
# @example
#   load_vm_state 100
#   echo "$STORED_VIRTIO_VERSION"
# Load VM state from file using Line by Line parsing
# Idea based on https://stackoverflow.com/questions/1521462/looping-through-the-content-of-a-file-in-bash
function load_vm_state() {
    local vmid=$1
    local state_file="$STATE_DIR/vm-${vmid}.state"
    
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    # Initialize variables with defaults
    local vmgenid="unknown"
    local virtio_version=""
    local qemu_ga_version=""
    local nag_active="false"
    local last_checked="0"
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Trim whitespace
        # Hope AI didn't lie^^ but it seems to work out in my tests
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        
        # Remove surrounding quotes if present
        value="${value#\"}"
        value="${value%\"}"
        
        # Match known keys only (whitelist approach)
        # Maybe a source for issues but safer than eval and safer than source / dot sourcing an "untrusted" file
        case "$key" in
            VMGENID) vmgenid="$value" ;;
            VIRTIO_VERSION) virtio_version="$value" ;;
            QEMU_GA_VERSION) qemu_ga_version="$value" ;;
            NAG_ACTIVE) nag_active="$value" ;;
            LAST_CHECKED) last_checked="$value" ;;
            LAST_CHECKED_DATE) ;; # Ignore, just for human readability
            *) log_warn "Unknown key in state file: $key" ;;
        esac
    done < "$state_file"
    
    # Export with validation
    export STORED_VMGENID="$vmgenid"
    export STORED_VIRTIO_VERSION="$virtio_version"
    export STORED_QEMU_GA_VERSION="$qemu_ga_version"
    export STORED_NAG_ACTIVE="$nag_active"
    export STORED_LAST_CHECKED="$last_checked"
    
    return 0
}

# @function should_show_nag
# @description Determine whether update notification should be displayed based on VM state and version changes
# @args vmid (string): Proxmox VM ID
#       current_virtio (string): Currently installed VirtIO version
#       latest_virtio (string): Latest available VirtIO version
#       current_qemu_ga (string): Currently installed QEMU GA version
#       latest_qemu_ga (string): Latest available QEMU GA version
#       current_vmgenid (string): Current VM generation ID
# @returns 0=show/update nag, 1=no action, 2=remove nag (VM up to date), 3=nag muted
# @example
#   should_show_nag 100 "0.1.283" "0.1.285" "9.0.0" "9.1.0" "$vmgenid"
#   case $? in
#     0) show_or_update_nag ;;   # create or refresh nag for this VM
#     1) : ;;                    # no action needed (nag state already correct / no nag required)
#     2) remove_nag ;;           # VM is up to date, remove any existing nag
#     3) nag_muted ;;            # nag explicitly muted for this VM
#   esac
# Check if nag should be displayed for this VM based on current and stored state
function should_show_nag() {
    local vmid=$1
    local current_virtio=$2
    local latest_virtio=$3
    local current_qemu_ga=$4
    local latest_qemu_ga=$5
    local current_vmgenid=$6
    
    # Load previous state
    if ! load_vm_state "$vmid"; then
        # No state exists, this is first run
        log_debug "No state for VM $vmid, will check for updates"
        return 0
    fi
    
    # Check if this is the same VM instance
    if [[ "$STORED_VMGENID" != "$current_vmgenid" ]]; then
        log_info "VM $vmid was cloned/restored/replaced (old genid: $STORED_VMGENID, new genid: $current_vmgenid) - treating as new VM"
        # This is a different VM instance, start fresh
        return 0
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
    
    # If both are up to date, no nag is needed
    if [[ "$virtio_uptodate" == true && "$qemu_ga_uptodate" == true ]]; then
        log_debug "VM $vmid is up to date (VirtIO: $current_virtio, QEMU-GA: $current_qemu_ga)"
        
        # If nag was previously active, remove it
        if [[ "$STORED_NAG_ACTIVE" == "true" ]]; then
            log_info "VM $vmid is now up to date, removing update nag"
            return 2  # Special exit code: remove existing nag
        fi
        
        return 1  # No nag needed
    fi
    
    # Check if versions changed since last check (new update available)
    if [[ "$STORED_VIRTIO_VERSION" != "$current_virtio" ]] || \
       [[ "$STORED_QEMU_GA_VERSION" != "$current_qemu_ga" ]]; then
        log_debug "VM $vmid versions changed since last check, showing nag"
        return 0  # Show nag
    fi
    
    # Same installed versions as before and nag already shown, but VM is still not up to date.
    # Return 0 so the nag can be refreshed (e.g., if latest_* changed).
    if [[ "$STORED_NAG_ACTIVE" == "true" ]]; then
        log_debug "VM $vmid nag already active, refreshing nag state"
        return 0  # Nag already shown; allow caller to refresh/update it
    fi
    
    # Default: show nag if updates available
    return 0
}

# @function cleanup_stale_state_files
# @description Remove state files for VMs that no longer exist in the Proxmox cluster
# @args active_vmids (string): JSON object with VM IDs as keys
# @returns 0 on success; removes matching .state files from STATE_DIR
# @example
#   cleanup_stale_state_files "$windows_vms"
# Clean up state files for VMs that no longer exist
function cleanup_stale_state_files() {
    local active_vmids=$1  # JSON object with VM IDs as keys
    
    if [[ ! -d "$STATE_DIR" ]]; then
        return 0
    fi
    
    shopt -s nullglob

    for state_file in "$STATE_DIR"/vm-*.state; do        
        # Extract VMID from filename
        local vmid=$(basename "$state_file" | sed -E 's/vm-([0-9]+)\.state/\1/')
        
        # Check if VM still exists
        if ! echo "$active_vmids" | jq -e ".\"$vmid\"" > /dev/null 2>&1; then
            log_info "Removing stale state file for non-existent VM $vmid"
            rm -f "$state_file"
        fi
    done

    shopt -u nullglob
}
