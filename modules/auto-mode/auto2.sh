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

if ! command -v jq >/dev/null 2>&1 && [ -x "$TOOLS_DIR/jq" ]; then
    JQ_BIN="$TOOLS_DIR/jq"
elif ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] jq not found, using raw JSON output${RESET}"
    JQ_BIN="cat"
fi

# ============ UTILS ============
socket_request() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    local cmd="$CURL $TIMEOUT -X $method"
    [[ -n "$data" ]] && cmd="$cmd -H \"Content-Type: application/json\" -d '$data'"
    cmd="$cmd http://localhost$endpoint 2>/dev/null"
    eval "$cmd"
}

# ===================================================
# Borders - Perfect alignment even with color output
# ===================================================

# TOTAL WIDTH CALCULATED FROM COLUMNS
# | 20 | 15 | 12 | 12 | 10 | 10 |
# + delimiters = exactly 92
BORDER_LEN=92

print_border() {
    printf "+"
    printf -- "-%.0s" $(seq 1 $((BORDER_LEN-2)))
    printf "+\n"
}

# Prints a row and allows ANSI color with %b
print_row() {
    local fmt="| %-20b | %-15b | %-12b | %-12b | %-10b | %-10b |\n"
    printf "$fmt" "$@"
}

# ============ LIST CONTAINERS ============
list_containers() {
    echo -e "${CYAN}Fetching Docker containers...${RESET}"
    local resp
    resp=$(socket_request "GET" "/containers/json?all=true")

    print_border
    print_row "Container ID" "Name" "Image" "Status" "Privileged" "Network"
    print_border

    if command -v jq >/dev/null 2>&1 || [ "$JQ_BIN" != "cat" ]; then
        local count
        count=$($JQ_BIN length <<<"$resp" 2>/dev/null)

        if [[ "$count" -eq 0 ]]; then
            print_row "${RED}NO CONTAINERS${RESET}" "" "" "" "" ""
            print_border
            return
        fi

        for i in $(seq 0 $((count-1))); do
            local id name image status priv network

            id=$($JQ_BIN -r ".[$i].Id[:12]" <<<"$resp")
            name=$($JQ_BIN -r ".[$i].Names[0]" <<<"$resp" | tr -d '/')
            image=$($JQ_BIN -r ".[$i].Image" <<<"$resp")
            status=$($JQ_BIN -r ".[$i].Status" <<<"$resp")
            priv=$($JQ_BIN -r ".[$i].HostConfig.Privileged" <<<"$resp")
            network=$($JQ_BIN -r ".[$i].HostConfig.NetworkMode" <<<"$resp")

            # Colors
            [[ "$priv" == "true" ]] && priv="${RED}YES${RESET}" || priv="${GREEN}NO${RESET}"
            [[ "$network" == "host" ]] && network="${YELLOW}$network${RESET}"

            print_row "$id" "$name" "$image" "$status" "$priv" "$network"
        done
    else
        echo "$resp"
    fi

    print_border
}

# ============ MAIN ============
if [[ ! -S "$SOCK" ]]; then
    echo -e "${RED}[ERR] Docker socket not found at $SOCK${RESET}"
    exit 1
fi

list_containers
