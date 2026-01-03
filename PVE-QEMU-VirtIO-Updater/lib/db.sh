#!/bin/env bash

# Functions linked to the json state store

function init_data_json() {
    if [ ! -f "$DATA_JSON" ]; then
        echo "{}" > "$DATA_JSON"
    fi
}

function add_vm_to_data_json() {
    local vmid="$1"

    # Check if VM already exists in the JSON
    local exists
    exists=$(jq --arg vmid "$vmid" 'has($vmid)' "$DATA_JSON")

    if [ "$exists" != "true" ]; then
        # Add new VM entry
        jq --arg vmid "$vmid" '.[$vmid] = {}' "$DATA_JSON" > "${DATA_JSON}.tmp" && mv "${DATA_JSON}.tmp" "$DATA_JSON"
    fi
}

function update_data_json() {
    local vmid="$1"
    local key="$2"
    local value="$3"

    # Read existing data
    local existing_data
    existing_data=$(jq --arg vmid "$vmid" --arg key "$key" --arg value "$value" \
        '.[$vmid][$key] = $value' "$DATA_JSON")

    # Write updated data back to the file
    echo "$existing_data" > "$DATA_JSON"
}
