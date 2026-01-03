#!/bin/env bash

# Functions linked to the json state store

function init_data_json() {
    if [ ! -f "$DATA_JSON" ]; then
        echo "{}" > "$DATA_JSON"
    fi
}

