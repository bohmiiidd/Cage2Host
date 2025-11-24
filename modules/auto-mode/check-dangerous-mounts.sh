#!/bin/bash

# Quick check for dangerous mounts
echo "Checking for dangerous volume mounts..."

dangerous_found=false

# Check running containers
docker ps --format "{{.Names}}" | while read container; do
    echo "Checking container: $container"
    
    # Check mounts for dangerous paths
    docker inspect "$container" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' | \
    while read -r mount; do
        if [[ -n "$mount" ]]; then
            source=$(echo "$mount" | cut -d' ' -f1)
            dest=$(echo "$mount" | cut -d' ' -f3)
            
            # Check for dangerous paths
            for path in "/" "/etc" "/var/run" "/home" "/boot" "/proc" "/sys"; do
                if [[ "$source" == "$path"* ]] || [[ "$dest" == "$path"* ]]; then
                    echo "DANGEROUS MOUNT: $mount"
                    dangerous_found=true
                fi
            done
        fi
    done
done

if $dangerous_found; then
    echo "WARNING: Dangerous mounts detected!"
    exit 1
else
    echo "No dangerous mounts found."
    exit 0
fi