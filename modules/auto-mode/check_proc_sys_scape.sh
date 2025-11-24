#!/bin/bash

# Script to detect writable /proc/sys escape vulnerabilities
# Checks for kernel.core_pattern overwrite, modprobe_path injection, and configurable sysctls

set -e

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

WARNING_FOUND=false
CONTAINER_PRIVILEGED=false

echo -e "${YELLOW}Checking for /proc/sys escape vulnerabilities...${NC}"
echo "================================================================"

# Function to check if container is privileged
check_privileged() {
    local container_id="$1"
    local privileged=$(docker inspect "$container_id" --format='{{.HostConfig.Privileged}}')
    
    if [[ "$privileged" == "true" ]]; then
        CONTAINER_PRIVILEGED=true
        return 0
    fi
    return 1
}

# Function to check dangerous sysctls
check_dangerous_sysctls() {
    local container_id="$1"
    local container_name="$2"
    
    echo -e "\n${BLUE}Checking sysctls for $container_name:${NC}"
    
    # Get configured sysctls
    local sysctls=$(docker inspect "$container_id" --format='{{range $k, $v := .HostConfig.Sysctls}}{{$k}}={{$v}}{{"\n"}}{{end}}')
    
    if [[ -z "$sysctls" ]]; then
        echo -e "  ${GREEN}No custom sysctls configured${NC}"
        return
    fi
    
    # Dangerous sysctl patterns
    local dangerous_sysctls=(
        "kernel.core_pattern"
        "kernel.modprobe"
        "net.core"
        "kernel.kptr_restrict"
        "kernel.dmesg_restrict"
        "kernel.perf_event_paranoid"
        "kernel.unprivileged_bpf_disabled"
    )
    
    while IFS='=' read -r key value; do
        if [[ -n "$key" ]]; then
            local is_dangerous=false
            
            for dangerous in "${dangerous_sysctls[@]}"; do
                if [[ "$key" == "$dangerous"* ]]; then
                    is_dangerous=true
                    break
                fi
            done
            
            if $is_dangerous; then
                echo -e "  ${RED}DANGEROUS SYSCTL${NC} - $key=$value"
                echo -e "    ${YELLOW}This sysctl could be abused for container escape${NC}"
                WARNING_FOUND=true
            else
                echo -e "  ${GREEN}SAFE SYSCTL${NC} - $key=$value"
            fi
        fi
    done <<< "$sysctls"
}

# Function to check for core_pattern overwrite capability
check_core_pattern_vulnerability() {
    local container_id="$1"
    local container_name="$2"
    
    echo -e "\n${BLUE}Checking kernel.core_pattern vulnerability for $container_name:${NC}"
    
    # Check if container has SYS_ADMIN capability or is privileged
    local capabilities=$(docker inspect "$container_id" --format='{{.HostConfig.CapAdd}}')
    local security_opt=$(docker inspect "$container_id" --format='{{.HostConfig.SecurityOpt}}')
    
    # Check for SYS_ADMIN capability
    if [[ "$capabilities" == *"SYS_ADMIN"* ]] || check_privileged "$container_id"; then
        echo -e "  ${RED}VULNERABLE${NC} - Container has SYS_ADMIN capability or is privileged"
        echo -e "    ${YELLOW}Can potentially overwrite kernel.core_pattern for container escape${NC}"
        WARNING_FOUND=true
        
        # Check if core_pattern is writable
        echo -e "  ${YELLOW}Testing /proc/sys/kernel/core_pattern writability...${NC}"
        
        # Try to check if core_pattern can be written to
        if docker exec "$container_id" sh -c 'test -w /proc/sys/kernel/core_pattern && echo "WRITABLE" || echo "NOT_WRITABLE"' 2>/dev/null | grep -q "WRITABLE"; then
            echo -e "  ${RED}CRITICAL${NC} - /proc/sys/kernel/core_pattern is writable"
            echo -e "    ${YELLOW}Container can modify core_pattern for privilege escalation${NC}"
        fi
    else
        echo -e "  ${GREEN}SAFE${NC} - No SYS_ADMIN capability and not privileged"
    fi
}

# Function to check for modprobe_path injection
check_modprobe_injection() {
    local container_id="$1"
    local container_name="$2"
    
    echo -e "\n${BLUE}Checking modprobe_path injection vulnerability for $container_name:${NC}"
    
    # Check for SYS_MODULE capability or privileged
    local capabilities=$(docker inspect "$container_id" --format='{{.HostConfig.CapAdd}}')
    
    if [[ "$capabilities" == *"SYS_MODULE"* ]] || check_privileged "$container_id"; then
        echo -e "  ${RED}VULNERABLE${NC} - Container has SYS_MODULE capability or is privileged"
        echo -e "    ${YELLOW}Can potentially modify kernel.modprobe for container escape${NC}"
        WARNING_FOUND=true
        
        # Check if modprobe path is writable
        echo -e "  ${YELLOW}Testing /proc/sys/kernel/modprobe writability...${NC}"
        
        if docker exec "$container_id" sh -c 'test -w /proc/sys/kernel/modprobe && echo "WRITABLE" || echo "NOT_WRITABLE"' 2>/dev/null | grep -q "WRITABLE"; then
            echo -e "  ${RED}CRITICAL${NC} - /proc/sys/kernel/modprobe is writable"
            echo -e "    ${YELLOW}Container can hijack modprobe execution${NC}"
        fi
    else
        echo -e "  ${GREEN}SAFE${NC} - No SYS_MODULE capability and not privileged"
    fi
}

# Function to check writable proc mounts
check_writable_proc_mounts() {
    local container_id="$1"
    local container_name="$2"
    
    echo -e "\n${BLUE}Checking /proc mounts for $container_name:${NC}"
    
    # Check if /proc is mounted with dangerous options
    local mounts=$(docker inspect "$container_id" --format='{{json .Mounts}}')
    
    if command -v jq >/dev/null 2>&1; then
        local mount_count=$(echo "$mounts" | jq length)
        
        for ((i=0; i<mount_count; i++)); do
            local source=$(echo "$mounts" | jq -r ".[$i].Source")
            local destination=$(echo "$mounts" | jq -r ".[$i].Destination")
            local type=$(echo "$mounts" | jq -r ".[$i].Type")
            
            if [[ "$destination" == "/proc"* ]]; then
                echo -e "  ${YELLOW}WARNING${NC} - Proc mount found: $source -> $destination"
                echo -e "    ${YELLOW}Type: $type${NC}"
                
                # Check if it's a bind mount of host /proc
                if [[ "$source" == "/proc" ]]; then
                    echo -e "  ${RED}CRITICAL${NC} - Host /proc is bind-mounted into container"
                    WARNING_FOUND=true
                fi
            fi
        done
    fi
    
    # Check if /proc/sys is writable
    echo -e "  ${YELLOW}Testing /proc/sys writability...${NC}"
    if docker exec "$container_id" sh -c 'find /proc/sys -maxdepth 1 -type d -writable 2>/dev/null | head -5' 2>/dev/null | grep -q "/proc/sys"; then
        echo -e "  ${RED}VULNERABLE${NC} - /proc/sys contains writable directories"
        WARNING_FOUND=true
    else
        echo -e "  ${GREEN}SAFE${NC} - /proc/sys is not writable"
    fi
}

# Function to check security options
check_security_options() {
    local container_id="$1"
    local container_name="$2"
    
    echo -e "\n${BLUE}Checking security options for $container_name:${NC}"
    
    # Check for AppArmor profile
    local apparmor=$(docker inspect "$container_id" --format='{{.AppArmorProfile}}')
    if [[ -z "$apparmor" || "$apparmor" == "unconfined" ]]; then
        echo -e "  ${YELLOW}WARNING${NC} - No AppArmor profile or running unconfined"
        WARNING_FOUND=true
    else
        echo -e "  ${GREEN}SECURE${NC} - AppArmor profile: $apparmor"
    fi
    
    # Check for Seccomp profile
    local seccomp=$(docker inspect "$container_id" --format='{{.HostConfig.SecurityOpt}}')
    if [[ "$seccomp" == "[]" || "$seccomp" == *"unconfined"* ]]; then
        echo -e "  ${YELLOW}WARNING${NC} - No Seccomp profile or running unconfined"
        WARNING_FOUND=true
    else
        echo -e "  ${GREEN}SECURE${NC} - Seccomp profile enabled"
    fi
    
    # Check for no-new-privileges
    if docker inspect "$container_id" --format='{{.Config.Attributes}}' | grep -q "no-new-privileges"; then
        echo -e "  ${GREEN}SECURE${NC} - No-new-privileges enabled"
    else
        echo -e "  ${YELLOW}WARNING${NC} - No-new-privileges not enabled"
        WARNING_FOUND=true
    fi
}

# Function to analyze container for /proc/sys vulnerabilities
analyze_container() {
    local container_id="$1"
    local container_name="$2"
    local image="$3"
    
    echo -e "\n${YELLOW}=========================================================${NC}"
    echo -e "${YELLOW}Analyzing container: $container_name ($container_id)${NC}"
    echo -e "${YELLOW}Image: $image${NC}"
    
    # Reset privileged flag for each container
    CONTAINER_PRIVILEGED=false
    
    # Run all checks
    check_privileged "$container_id"
    check_dangerous_sysctls "$container_id" "$container_name"
    check_core_pattern_vulnerability "$container_id" "$container_name"
    check_modprobe_injection "$container_id" "$container_name"
    check_writable_proc_mounts "$container_id" "$container_name"
    check_security_options "$container_id" "$container_name"
}

# Function to check docker run commands in history
check_docker_history() {
    echo -e "\n${BLUE}Checking recent docker run commands for dangerous options...${NC}"
    
    if history | grep "docker run" | tail -10 | while read -r line; do
        if [[ "$line" == *"--privileged"* ]] || \
           [[ "$line" == *"--cap-add=SYS_ADMIN"* ]] || \
           [[ "$line" == *"--cap-add=SYS_MODULE"* ]] || \
           [[ "$line" == *"sysctl"* ]]; then
            echo -e "  ${YELLOW}Found potentially dangerous command:${NC}"
            echo -e "    $line"
        fi
    done; then
        echo -e "  ${GREEN}No obviously dangerous docker run commands found in history${NC}"
    fi
}

# Main execution

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Docker is not running or current user doesn't have permissions${NC}"
    exit 1
fi

# Get running containers
containers=$(docker ps --format "{{.ID}}|{{.Names}}|{{.Image}}" 2>/dev/null)

if [[ -z "$containers" ]]; then
    echo -e "${GREEN}No running containers found${NC}"
else
    echo "Found $(echo "$containers" | wc -l) running container(s)"
    
    # Analyze each container
    while IFS='|' read -r container_id container_name image; do
        if [[ -n "$container_id" ]]; then
            analyze_container "$container_id" "$container_name" "$image"
        fi
    done <<< "$containers"
fi

# Check docker history
check_docker_history

# Summary and recommendations
echo -e "\n${YELLOW}================================================================"
echo -e "SECURITY ASSESSMENT SUMMARY${NC}"
echo "================================================================"

if $WARNING_FOUND; then
    echo -e "${RED}CRITICAL: /proc/sys escape vulnerabilities detected!${NC}"
    echo -e "\n${YELLOW}RECOMMENDATIONS:${NC}"
    echo "1. Avoid using --privileged flag"
    echo "2. Remove SYS_ADMIN and SYS_MODULE capabilities unless absolutely necessary"
    echo "3. Use read-only /proc mounts when possible"
    echo "4. Implement AppArmor/Seccomp profiles"
    echo "5. Enable no-new-privileges security option"
    echo "6. Avoid dangerous sysctl configurations"
    echo "7. Use --security-opt=no-new-privileges:true"
    echo "8. Consider using gVisor or Kata Containers for additional isolation"
    echo -e "\n${RED}These vulnerabilities could allow container escape and host system compromise!${NC}"
    exit 1
else
    echo -e "${GREEN}No critical /proc/sys escape vulnerabilities detected${NC}"
    echo -e "\n${YELLOW}Best practices confirmed:${NC}"
    echo "✓ No privileged containers detected"
    echo "✓ No dangerous sysctl configurations"
    echo "✓ Appropriate security options in place"
    exit 0
fi