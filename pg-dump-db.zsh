#!/bin/zsh

# Path to your .pg_service.conf file
PG_SERVICE_CONF="$HOME/.pg_service.conf"

# Check if the file exists
if [[ ! -f "$PG_SERVICE_CONF" ]]; then
    echo "Error: .pg_service.conf file not found at $PG_SERVICE_CONF"
    exit 1
fi

# Extract service names from the .pg_service.conf file
services=$(grep '^\[' "$PG_SERVICE_CONF" | tr -d '[]')

# Check if any services were found
if [[ -z "$services" ]]; then
    echo "No services found in $PG_SERVICE_CONF"
    exit 1
fi

# Use fzf to select a service
selected_service=$(echo "$services" | fzf --prompt="Select a database service for dump: ")

# Check if a service was selected
if [[ -z "$selected_service" ]]; then
    echo "No service selected."
    exit 1
fi

# Connect using pgcli
dump_file="${selected_service}_$(date +'%Y-%m-%d_%H-%M-%S').sql"
pg_dump service="$selected_service" > $dump_file
echo "Backup was saved into ${dump_file}"
