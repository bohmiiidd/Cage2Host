#!/bin/bash

# Quick /proc/sys escape vulnerability detection

echo "Quick /proc/sys Escape Vulnerability Check"
echo "=========================================="

docker ps --format "{{.Names}}" | while read container; do
    echo "Checking container: $container"
    
    # Check privileged
    if docker inspect "$container" --format='{{.HostConfig.Privileged}}' | grep -q "true"; then
        echo "  ❌ PRIVILEGED CONTAINER - High risk for /proc/sys escape"
    fi
    
    # Check SYS_ADMIN capability
    if docker inspect "$container" --format='{{.HostConfig.CapAdd}}' | grep -q "SYS_ADMIN"; then
        echo "  ❌ SYS_ADMIN capability enabled - Can modify core_pattern"
    fi
    
    # Check SYS_MODULE capability  
    if docker inspect "$container" --format='{{.HostConfig.CapAdd}}' | grep -q "SYS_MODULE"; then
        echo "  ❌ SYS_MODULE capability enabled - Can modify modprobe_path"
    fi
    
    # Check dangerous sysctls
    docker inspect "$container" --format='{{range $k, $v := .HostConfig.Sysctls}}{{$k}}={{$v}}{{"\n"}}{{end}}' | \
    grep -E "(kernel.core_pattern|kernel.modprobe)" && \
    echo "  ❌ Dangerous sysctl configured"
    
    # Quick writability test
    if docker exec "$container" sh -c 'test -w /proc/sys/kernel/core_pattern 2>/dev/null && echo "WRITABLE"' | grep -q "WRITABLE"; then
        echo "  ❌ CRITICAL: core_pattern is writable"
    fi
done

echo "=========================================="
echo "Quick check completed"