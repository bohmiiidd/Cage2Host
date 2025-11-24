#!/bin/bash
# ============================================
# Docker Container Enumerator - Pretty & Colored
# ============================================

SOCK="${DOCKER_SOCKET:-/var/run/docker.sock}"
CURL="curl --silent --unix-socket $SOCK"
TIMEOUT="--max-time 5"

# ============ COLORS ============
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ============ TOOLS ============
TOOLS_DIR="$(dirname "$0")/../auto-mode"
JQ_BIN="jq"

# Try to find jq
if ! command -v jq >/dev/null 2>&1 && [ -x "$TOOLS_DIR/jq" ]; then
    JQ_BIN="$TOOLS_DIR/jq"
elif ! command -v jq >/dev/null 2>&1; then
    JQ_BIN="cat"  # fallback
    echo -e "${YELLOW}[WARN] jq not found, raw JSON output will be used${RESET}"
fi

# ============ UTILS ============
socket_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    cmd="$CURL $TIMEOUT -X $method"
    if [ -n "$data" ]; then
        cmd="$cmd -H \"Content-Type: application/json\" -d '$data'"
    fi
    cmd="$cmd http://localhost$endpoint 2>/dev/null"
    eval "$cmd"
}

# ============ BORDER UTILS ============
print_border() {
    local len="$1"
    printf "+%0.s-" $(seq 1 "$len")
    echo "+"
}

print_row() {
    local cols=("$@")
    local fmt="| %-20s | %-15s | %-12s | %-12s | %-10s | %-10s |\n"
    printf "%b" "$(printf "$fmt" "${cols[@]}")"
}

# ============ LIST CONTAINERS ============
list_containers() {
    echo -e "${CYAN}Fetching Docker containers...${RESET}"
    local resp
    resp=$(socket_request "GET" "/containers/json?all=true")

    # Header
    local border_len=92
    print_border "$border_len"
    printf "| %-20s | %-15s | %-12s | %-12s | %-10s | %-10s |\n" \
           "Container ID" "Name" "Image" "Status" "Privileged" "Network"
    print_border "$border_len"

    # Loop through containers
    if command -v jq >/dev/null 2>&1 || [ "$JQ_BIN" != "cat" ]; then
        local count
        count=$($JQ_BIN length <<<"$resp" 2>/dev/null)
        if [ "$count" -eq 0 ]; then
            echo -e "| No containers found${RESET}"
            print_border "$border_len"
            return
        fi

        for i in $(seq 0 $((count - 1))); do
            local id name image status priv network
            id=$($JQ_BIN -r ".[$i].Id[:12]" <<<"$resp")
            name=$($JQ_BIN -r ".[$i].Names[0]" <<<"$resp" | tr -d '/')
            image=$($JQ_BIN -r ".[$i].Image" <<<"$resp")
            status=$($JQ_BIN -r ".[$i].Status" <<<"$resp")
            priv=$($JQ_BIN -r ".[$i].HostConfig.Privileged" <<<"$resp")
            network=$($JQ_BIN -r ".[$i].HostConfig.NetworkMode" <<<"$resp")

            # Color highlighting
            if [ "$priv" = "true" ]; then
                priv="${RED}YES${RESET}"
            else
                priv="${GREEN}NO${RESET}"
            fi

            if [ "$network" = "host" ]; then
                network="${YELLOW}$network${RESET}"
            fi

            print_row "$id" "$name" "$image" "$status" "$priv" "$network"
        done
    else
        echo "$resp" | while read -r line; do
            echo "$line"
        done
    fi

    print_border "$border_len"
}

# ============ MAIN ============
if [[ ! -S "$SOCK" ]]; then
    echo -e "${RED}[ERR] Docker socket not found at $SOCK${RESET}"
    exit 1
fi

list_containers
