#!/bin/bash

# Container Escape & Kubernetes Misconfiguration Assessment Script
# Assesses various container escape vectors and misconfigurations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }


# Check if running in container
check_container() {
    log_info "Checking if running in container..."
    if grep -q docker /proc/self/cgroup 2>/dev/null || 
       [[ -f /.dockerenv ]] || 
       grep -q kubepods /proc/self/cgroup 2>/dev/null; then
        log_success "Running in container environment"
        return 0
    else
        log_warn "Not running in container (or detection failed)"
        return 1
    fi
}

# Namespace misconfiguration checks
check_namespace_misconfig() {
    log_info "Checking namespace misconfigurations..."
    
    # Check if we're in host namespaces
    if [[ "$(readlink /proc/1/ns/pid)" == "$(readlink /proc/self/ns/pid)" ]]; then
        log_warn "Container shares PID namespace with host"
    fi
    
    if [[ "$(readlink /proc/1/ns/net)" == "$(readlink /proc/self/ns/net)" ]]; then
        log_warn "Container shares NET namespace with host"
    fi
    
    if [[ "$(readlink /proc/1/ns/ipc)" == "$(readlink /proc/self/ns/ipc)" ]]; then
        log_warn "Container shares IPC namespace with host"
    fi
    
    # Check user namespace
    if [[ "$(readlink /proc/1/ns/user)" == "$(readlink /proc/self/ns/user)" ]]; then
        log_warn "Container shares USER namespace with host"
    fi
    
    # Check for privileged mode
    if [[ "$(cat /proc/self/status | grep CapEff | awk '{print $2}')" == "0000003fffffffff" ]]; then
        log_error "Container running in PRIVILEGED mode!"
    fi
}

# Cgroups v1/v2 writable paths
check_cgroups() {
    log_info "Checking cgroups configuration..."
    
    # Check cgroup version
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        log_info "Cgroups v2 detected"
        # Check writable cgroup paths
        find /sys/fs/cgroup -writable -type d 2>/dev/null | while read path; do
            if [[ "$path" != *"cgroup"* ]]; then continue; fi
            log_warn "Writable cgroup path: $path"
        done
    else
        log_info "Cgroups v1 detected"
        # Check writable cgroup paths in v1
        find /sys/fs/cgroup -writable -type d 2>/dev/null | while read path; do
            if [[ "$path" != *"cgroup"* ]]; then continue; fi
            log_warn "Writable cgroup path: $path"
        done
    fi
    
    # Check cgroup release_agent (v1 escape)
    if [[ -f /sys/fs/cgroup/release_agent ]]; then
        log_warn "Cgroup release_agent file exists"
        if [[ -w /sys/fs/cgroup/release_agent ]]; then
            log_error "Cgroup release_agent is WRITABLE - potential escape vector"
        fi
    fi
}

# Kernel LPE detection
check_kernel_lpe() {
    log_info "Checking kernel version for LPE vulnerabilities..."
    
    kernel_version=$(uname -r)
    log_info "Kernel version: $kernel_version"
    
    # Known vulnerable kernel versions (simplified check)
    vulnerable_versions=(
        "3.10.0" "4.15.0" "5.0.0" "5.1.0" "5.2.0" "5.3.0" 
        "5.4.0" "5.5.0" "5.6.0" "5.7.0" "5.8.0"
    )
    
    major_minor=$(echo "$kernel_version" | cut -d. -f1-2)
    for vuln_ver in "${vulnerable_versions[@]}"; do
        if [[ "$major_minor" == "$(echo $vuln_ver | cut -d. -f1-2)" ]]; then
            log_warn "Kernel version $kernel_version might be vulnerable to known LPE exploits"
            break
        fi
    done
    
    # Check for DirtyPipe/CVE-2022-0847
    if [[ "$kernel_version" =~ ^5\.8|5\.1[0-9]|5\.1[0-5]|5\.16\.[0-9]|5\.15\.[0-9]|5\.10\.[0-9][0-2] ]]; then
        log_warn "Kernel might be vulnerable to DirtyPipe (CVE-2022-0847)"
    fi
}

# Runtime escape vulnerabilities
check_runtime_escape() {
    log_info "Checking for runtime escape vulnerabilities..."
    
    # Check container runtime
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker detected"
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log_info "Docker version: $docker_version"
    fi
    
    if command -v containerd >/dev/null 2>&1; then
        log_info "Containerd detected"
    fi
    
    if command -v runc >/dev/null 2>&1; then
        log_info "Runc detected"
    fi
    
    # Check for known escape vectors
    if mount | grep -q "overlay on /proc"; then
        log_warn "Overlayfs mounted on /proc - potential escape vector"
    fi
    
    # Check /proc/sys/kernel/modules_disabled
    if [[ -f /proc/sys/kernel/modules_disabled ]] && [[ "$(cat /proc/sys/kernel/modules_disabled)" == "0" ]]; then
        log_warn "Kernel module loading enabled"
    fi
}

# Kubernetes misconfiguration
check_kubernetes_misconfig() {
    log_info "Checking Kubernetes misconfigurations..."
    
    # Check if we're in Kubernetes
    if [[ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]] || 
       grep -q kubepods /proc/self/cgroup 2>/dev/null; then
        log_info "Kubernetes environment detected"
        
        # Check service account tokens
        if [[ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]]; then
            log_warn "Service account token mounted"
            # Check if we can access Kubernetes API
            if curl -s -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
                   --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
                   "https://kubernetes.default.svc/api/v1/namespaces/default/pods" >/dev/null 2>&1; then
                log_error "Able to access Kubernetes API from container!"
            fi
        fi
        
        # Check for dangerous capabilities in pod
        if [[ -d /proc/1/root ]]; then
            caps=$(cat /proc/1/status | grep CapEff | awk '{print $2}')
            if [[ "$caps" == "0000003fffffffff" ]]; then
                log_error "Pod has privileged capabilities"
            fi
        fi
    else
        log_info "Not in Kubernetes environment (or detection failed)"
    fi
}

# Secrets and environment leaks
check_secrets_env() {
    log_info "Checking for secrets and environment leaks..."
    
    # Check environment variables
    log_info "Environment variables:"
    env | grep -i -E "pass|secret|key|token|cred" | while read line; do
        log_warn "Potential secret in env: $(echo $line | cut -d= -f1)"
    done
    
    # Check common secret locations
    secret_paths=(
        "/var/run/secrets"
        "/etc/kubernetes"
        "/root/.kube"
        "/home/*/.kube"
        "/tmp/secret"
        "/var/secret"
    )
    
    for path in "${secret_paths[@]}"; do
        if ls -d $path >/dev/null 2>&1; then
            log_warn "Secret path exists: $path"
        fi
    done
    
    # Check for exposed docker socket
    if [[ -S /var/run/docker.sock ]]; then
        log_error "Docker socket exposed at /var/run/docker.sock"
    fi
}

# Host filesystem exposure
check_host_fs_exposure() {
    log_info "Checking for host filesystem exposure..."
    
    # Check mounted volumes
    log_info "Mounted filesystems:"
    mount | grep -v -E "proc|sysfs|tmpfs|devpts|mqueue|shm" | while read line; do
        if echo "$line" | grep -q "on /host"; then
            log_error "Host filesystem mounted at /host"
        elif echo "$line" | grep -q "on /etc/hosts"; then
            log_warn "Host's /etc/hosts mounted"
        elif echo "$line" | grep -q "on /etc/resolv.conf"; then
            log_warn "Host's /etc/resolv.conf mounted"
        fi
    done
    
    # Check for root escape
    if [[ -d /host/etc ]] && [[ -f /host/etc/passwd ]]; then
        log_error "Host root filesystem accessible at /host"
    fi
    
    # Check proc mount
    if mount | grep -q "proc on /proc"; then
        log_info "Proc filesystem properly mounted"
    else
        log_warn "Proc filesystem might be host's"
    fi
}

# LSM policy weaknesses
check_lsm_policies() {
    log_info "Checking Linux Security Module policies..."
    
    # Check AppArmor
    if command -v apparmor_status >/dev/null 2>&1; then
        apparmor_status 2>/dev/null | grep -q "enforce" || log_warn "AppArmor not in enforcing mode"
    elif [[ -d /sys/kernel/security/apparmor ]]; then
        if grep -q "enforce" /sys/kernel/security/apparmor/profiles 2>/dev/null; then
            log_info "AppArmor profiles loaded"
        else
            log_warn "AppArmor not properly configured"
        fi
    else
        log_warn "AppArmor not detected"
    fi
    
    # Check Seccomp
    if grep -q "Seccomp:" /proc/self/status 2>/dev/null; then
        seccomp_mode=$(grep "Seccomp:" /proc/self/status | awk '{print $2}')
        case $seccomp_mode in
            0) log_warn "Seccomp disabled" ;;
            1) log_info "Seccomp in strict mode" ;;
            2) log_info "Seccomp in filter mode" ;;
            *) log_info "Seccomp mode: $seccomp_mode" ;;
        esac
    fi
    
    # Check SELinux
    if command -v sestatus >/dev/null 2>&1; then
        sestatus | grep -q "enabled" || log_warn "SELinux disabled"
    fi
}

# Main execution
main() {
    log_info "Starting container escape and misconfiguration assessment..."
    echo
    
    check_container
    echo
    check_namespace_misconfig
    echo
    check_cgroups
    echo
    check_kernel_lpe
    echo
    check_runtime_escape
    echo
    check_kubernetes_misconfig
    echo
    check_secrets_env
    echo
    check_host_fs_exposure
    echo
    check_lsm_policies
    
    echo
    log_info "Assessment complete. Review warnings and errors above."
    log_warn "This script provides basic checks - conduct thorough manual assessment for production environments."
}

# Run main function
main "$@"
