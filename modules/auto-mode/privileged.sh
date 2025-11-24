#!/bin/bash

# ============================================
#  Privileged Container Deep Enumeration
#       Red Team Edition - by bn
# ============================================

# ---------- Color Theme ----------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

SEPARATOR="----------------------------------------"

# ---------- Risk Score ----------
TOTAL_SCORE=0

add_score() {
    TOTAL_SCORE=$((TOTAL_SCORE + $1))
}

# ---------- Formatting ----------
section() {
    echo -e "\n${BLUE}[*] $1${NC}"
    echo "$SEPARATOR"
}

ok()  { echo -e "${GREEN}[+] $1${NC}"; }
bad() { echo -e "${RED}[-] $1${NC}"; }
warn(){ echo -e "${YELLOW}[!] $1${NC}"; }

# ============================================================
# 1. Container Detection
# ============================================================
check_container() {
section "Container Detection"

if [ -f "/.dockerenv" ]; then
    ok "Running inside Docker (/.dockerenv detected)"
    add_score 2
else
    bad "No /.dockerenv file"
fi

if grep -qE "(docker|kubepods)" /proc/1/cgroup; then
    ok "Cgroup indicates container environment"
else
    bad "Cgroup does not indicate Docker/K8s"
fi

if [ -n "$container" ]; then
    ok "Environment variable container=$container"
fi
}

# ============================================================
# 2. Privileged Mode Detection
# ============================================================
check_privileged() {
section "Privileged Mode Indicators"

# Running as root?
if [ "$(id -u)" -eq 0 ]; then
    ok "UID 0 detected (root inside container)"
    add_score 2
else
    bad "Not running as root"
fi

# Host procfs?
if mount | grep -q "/proc/sys rw"; then
    ok "Writable /proc/sys → potential kernel parameter modification"
    add_score 4
fi

# Access to host devices
for d in /dev/kmsg /dev/mem /dev/kmem /dev/sda; do
    if [ -e "$d" ]; then
        warn "Host-sensitive device accessible: $d"
        add_score 5
    fi
done
}

# ============================================================
# 3. Capabilities
# ============================================================
check_capabilities() {
section "Capabilities Enumeration"

if command -v capsh >/dev/null; then
    echo -e "${CYAN}Current Capabilities:${NC}"
    capsh --print | sed 's/^/   /'
fi

dangerous_caps=(
    cap_sys_admin
    cap_sys_ptrace
    cap_sys_module
    cap_dac_override
    cap_setfcap
)

for cap in "${dangerous_caps[@]}"; do
    if capsh --print | grep -q "$cap"; then
        warn "$cap available → dangerous"
        add_score 5
    fi
done
}

# ============================================================
# 4. Device Access
# ============================================================
check_devices() {
section "Device Access"

echo -e "${CYAN}Block devices:${NC}"
lsblk 2>/dev/null || echo "lsblk not available"

# /dev/kmsg writable?
if echo "test" > /dev/kmsg 2>/dev/null; then
    warn "/dev/kmsg writable → Kernel message injection!"
    add_score 6
fi
}

# ============================================================
# 5. Kernel Memory Exposure
# ============================================================
check_kernel_memory() {
section "Kernel Memory Exposure"

if [ -r /proc/kcore ]; then
    warn "/proc/kcore readable → raw kernel memory exposed!"
    add_score 8
fi

if [ -r /boot ]; then
    warn "/boot accessible → host bootloader accessible"
    add_score 4
fi
}

# ============================================================
# 6. Cgroup Escape Checks
# ============================================================
check_cgroups() {
section "Cgroup Escape Techniques"

if find /sys/fs/cgroup -name release_agent 2>/dev/null | grep -q release_agent ; then
    warn "release_agent found → potential escape (cgroups v1)"
    add_score 6
fi
}

# ============================================================
# 7. Namespace Misconfigurations
# ============================================================
check_namespaces() {
section "Namespace Analysis"

if unshare --user --mount true 2>/dev/null; then
    warn "Can create new namespaces → possible mount escape"
    add_score 5
fi

if grep -q '^0 ' /proc/self/uid_map; then
    warn "Container UID 0 maps to host UID 0 → REAL root"
    add_score 10
fi
}

# ============================================================
# 8. BPF Attack Surface
# ============================================================
check_bpf() {
section "BPF Exposure"

if [ -w /sys/kernel/debug/tracing ]; then
    warn "Tracing filesystem writable → BPF possible"
    add_score 6
fi

if grep -q "bpf" /proc/filesystems; then
    ok "BPF subsystem enabled"
fi
}

# ============================================================
# 9. LSM (AppArmor / Seccomp / SELinux)
# ============================================================
check_lsm() {
section "LSM (AppArmor, Seccomp, SELinux)"

# AppArmor
AA=$(cat /proc/self/attr/current 2>/dev/null)

if echo "$AA" | grep -q "unconfined"; then
    warn "AppArmor: unconfined"
    add_score 4
else
    ok "AppArmor: $AA"
fi

# Seccomp
SC=$(grep Seccomp /proc/self/status | awk '{print $2}')
if [ "$SC" = "0" ]; then
    warn "Seccomp disabled → no syscall filtering"
    add_score 4
else
    ok "Seccomp enabled (mode=$SC)"
fi

# SELinux
if command -v getenforce >/dev/null; then
    warn "SELinux mode: $(getenforce)"
fi
}

# ============================================================
# 10. Docker Escape
# ============================================================
check_docker_socket() {
section "Docker Socket Exposure"

if [ -S /var/run/docker.sock ]; then
    warn "Docker socket exposed → FULL HOST TAKEOVER"
    add_score 10

    if command -v docker >/dev/null; then
        docker ps >/dev/null 2>&1 && ok "Can execute Docker commands"
    fi
else
    bad "No Docker socket"
fi
}

# ============================================================
# 11. Kubernetes Checks
# ============================================================
check_kubernetes() {
section "Kubernetes Enumeration"

if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
    warn "Kubernetes service account token found"
    add_score 4
fi

if [ -n "$KUBERNETES_PORT" ]; then
    warn "Kubernetes cluster environment detected"
    add_score 3
fi
}

# ============================================================
# 12. Kernel Vulnerabilities
# ============================================================
check_kernel() {
section "Kernel Information"

echo "Kernel: $(uname -r)"
echo "Arch: $(uname -m)"

VERSION=$(uname -r | cut -d '-' -f1)

if printf '%s\n' "4.14" "$VERSION" | sort -V | head -n1 | grep -q "4.14"; then
    warn "Kernel may be vulnerable to DirtyCow / DirtyPipe"
    add_score 3
fi
}

# ============================================================
# MAIN
# ============================================================
echo -e "${MAGENTA}
===============================================
   PRIVILEGED CONTAINER ENUMERATION TOOL
===============================================
${NC}"

check_container
check_privileged
check_capabilities
check_devices
check_kernel_memory
check_cgroups
check_namespaces
check_bpf
check_lsm
check_docker_socket
check_kubernetes
check_kernel

echo -e "\n${CYAN}Final Privilege Risk Score: ${MAGENTA}$TOTAL_SCORE / 100 ${NC}"

if [ "$TOTAL_SCORE" -ge 40 ]; then
    echo -e "${RED}HIGH RISK: Container is near‑privileged or fully privileged!${NC}"
elif [ "$TOTAL_SCORE" -ge 20 ]; then
    echo -e "${YELLOW}MEDIUM RISK: Potential breakout vectors exist.${NC}"
else
    echo -e "${GREEN}LOW RISK: Container seems isolated.${NC}"
fi

echo ""
