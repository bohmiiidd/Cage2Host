#!/usr/bin/env bash
# socket-hopper.sh
# Container Hopper: list / run / exec / switch using Docker UNIX socket (API mode only)
# Safe: no host escape attempts. Requires access to /var/run/docker.sock
set -euo pipefail

# ----------------------------
# Config & tools
# ----------------------------
SOCK="/var/run/docker.sock"
CURL="curl --silent --unix-socket $SOCK"
TIMEOUT="--max-time 10"

# Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

# Tools detection
JQ="$(command -v jq || true)"
SOCAT="$(command -v socat || true)"

if [[ ! -S "$SOCK" ]]; then
    echo -e "${RED}[ERR] Docker socket not found at $SOCK or not a socket.${RESET}"
    exit 2
fi

if [[ -z "$JQ" ]]; then
    echo -e "${YELLOW}[WARN] jq not found — output will be raw JSON where jq is used.${RESET}"
fi

# ----------------------------
# Helpers
# ----------------------------
api_get() {
    local path="$1"
    $CURL $TIMEOUT "http://localhost${path}"
}

api_post() {
    local path="$1" payload="${2:-}"
    if [[ -n "$payload" ]]; then
        $CURL $TIMEOUT -H "Content-Type: application/json" -X POST -d "$payload" "http://localhost${path}"
    else
        $CURL $TIMEOUT -X POST "http://localhost${path}"
    fi
}

api_delete() {
    local path="$1"
    $CURL $TIMEOUT -X DELETE "http://localhost${path}"
}

shortid() { echo "$1" | cut -c1-12; }

# ----------------------------
# Commands
# ----------------------------
cmd_list() {
    echo -e "${CYAN}== Containers (all) ==${RESET}"
    local raw
    raw="$(api_get "/containers/json?all=true")"
    if [[ -n "$JQ" ]]; then
        echo "$raw" | jq -r '.[] | "\(.Id[0:12])\t\(.Names[0] // "")\t\(.Image)\t\(.State)\t\(.Status)"' \
            | column -t -s $'\t'
    else
        echo "$raw"
    fi
}

cmd_run() {
    # Usage: run <image> [--name NAME] [--detach] -- <cmd...>
    local image="" name="" detach=false
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2;;
            --detach|-d) detach=true; shift;;
            --) shift; args=("$@"); break;;
            *) 
                if [[ -z "$image" ]]; then image="$1"; else args+=("$1"); fi
                shift;;
        esac
    done

    if [[ -z "$image" ]]; then
        echo -e "${RED}[ERR] run requires an image name.${RESET}"
        echo "Usage: $0 run <image> [--name NAME] [--detach] -- <cmd...>"
        exit 3
    fi

    # Build payload
    local cmd_json=""
    if [[ ${#args[@]} -gt 0 ]]; then
        # turn args into JSON array
        local arr='['
        for a in "${args[@]}"; do
            # escape quotes in arg
            a="${a//\"/\\\"}"
            arr+=\"${a}\",
        done
        arr="${arr%,}]"
        cmd_json="\"Cmd\": $arr,"
    fi

    local name_field=""
    if [[ -n "$name" ]]; then
        name_field="?name=$(printf '%s' "$name" | sed 's/ /%20/g')"
    fi

    local payload=$(cat <<EOF
{
  "Image": "$image",
  $cmd_json
  "OpenStdin": false,
  "Tty": false
}
EOF
)

    echo -e "${YELLOW}[*] Creating container from image: ${CYAN}$image${RESET}"
    local create_resp
    create_resp=$(api_post "/containers/create${name_field}" "$payload")
    local cid
    if [[ -n "$JQ" ]]; then
        cid=$(echo "$create_resp" | jq -r '.Id // empty')
    else
        cid=$(echo "$create_resp" | awk -F\" '/Id/ {print $4; exit}')
    fi

    if [[ -z "$cid" ]]; then
        echo -e "${RED}[ERR] Failed to create container.${RESET}"
        echo "$create_resp"
        exit 4
    fi

    cid=$(shortid "$cid")
    echo -e "${GREEN}[+] Created container: ${cid}${RESET}"

    echo -e "${YELLOW}[*] Starting container ${cid}...${RESET}"
    api_post "/containers/${cid}/start" >/dev/null
    echo -e "${GREEN}[+] Started.${RESET}"

    if [[ "$detach" == "true" ]]; then
        echo -e "${GREEN}[+] Run complete (detached). Container ID: ${cid}${RESET}"
        return 0
    fi

    echo -e "${YELLOW}[*] Fetching logs (stdout+stderr) ...${RESET}"
    api_get "/containers/${cid}/logs?stdout=true&stderr=true&follow=false&tail=200"
}

cmd_exec_noninteractive() {
    # Usage: exec <container> -- <cmd...>
    local container="$1"; shift
    if [[ -z "$container" ]]; then
        echo -e "${RED}[ERR] exec requires container id or name.${RESET}"
        exit 5
    fi
    # look for '--'
    if [[ "$1" == "--" ]]; then shift; fi
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}[ERR] exec requires a command.${RESET}"
        exit 6
    fi

    # build JSON array for Cmd
    local arr='['
    for a in "$@"; do
        a="${a//\"/\\\"}"
        arr+="\"$a\","
    done
    arr="${arr%,}]"

    local payload=$(cat <<EOF
{
  "AttachStdout": true,
  "AttachStderr": true,
  "AttachStdin": false,
  "Tty": false,
  "Cmd": $arr
}
EOF
)

    local exec_resp
    exec_resp=$(api_post "/containers/${container}/exec" "$payload")
    local exec_id
    if [[ -n "$JQ" ]]; then
        exec_id=$(echo "$exec_resp" | jq -r '.Id // empty')
    else
        exec_id=$(echo "$exec_resp" | awk -F\" '/Id/ {print $4; exit}')
    fi

    if [[ -z "$exec_id" ]]; then
        echo -e "${RED}[ERR] Failed to create exec.${RESET}"
        echo "$exec_resp"
        exit 7
    fi

    # start exec (non-interactive)
    local out
    out=$(api_post "/exec/${exec_id}/start" '{"Detach":false,"Tty":false}' 2>/dev/null || true)
    printf "%s\n" "$out"
}

cmd_exec_interactive() {
    # Usage: exec-attach <container> [shell-or-cmd...]
    # requires socat
    local container="$1"; shift
    if [[ -z "$container" ]]; then
        echo -e "${RED}[ERR] exec-attach requires container id or name.${RESET}"
        exit 8
    fi

    local cmd=( "/bin/sh" "-i" )
    if [[ $# -gt 0 ]]; then
        cmd=( "$@" )
    fi

    # build cmd json array
    local arr='['
    for a in "${cmd[@]}"; do
        a="${a//\"/\\\"}"
        arr+="\"$a\","
    done
    arr="${arr%,}]"

    local payload=$(cat <<EOF
{
  "AttachStdin": true,
  "AttachStdout": true,
  "AttachStderr": true,
  "Tty": true,
  "Cmd": $arr
}
EOF
)

    local exec_resp
    exec_resp=$(api_post "/containers/${container}/exec" "$payload")
    local exec_id
    if [[ -n "$JQ" ]]; then
        exec_id=$(echo "$exec_resp" | jq -r '.Id // empty')
    else
        exec_id=$(echo "$exec_resp" | awk -F\" '/Id/ {print $4; exit}')
    fi

    if [[ -z "$exec_id" ]]; then
        echo -e "${RED}[ERR] Failed to create exec.${RESET}"
        echo "$exec_resp"
        exit 9
    fi

    echo -e "${GREEN}[+] Exec created: ${exec_id}${RESET}"

    if [[ -n "$SOCAT" ]]; then
        echo -e "${YELLOW}[*] Attaching interactively using socat... (Ctrl-D or exit to detach)${RESET}"
        # Prepare HTTP request with proper CRLF and Upgrade headers for hijack
        # We'll use socat to send the HTTP request and bridge to STDIO for raw upgraded stream.
        # Compute body and content-length
        local body='{"Detach":false,"Tty":true}'
        local body_len=${#body}

        # Build raw HTTP request (must use CRLF)
        # Use printf to ensure \r\n sequences
        printf "POST /exec/%s/start HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: tcp\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" \
            "$exec_id" "$body_len" "$body" \
            | $SOCAT - EXEC:"openssl s_client -no_ign_eof -quiet /dev/null",nofork 2>/dev/null \
            >/dev/null 2>&1 || true

        # The above opens a complicated openssl wrapper on systems without raw unix socket piping to STDIO.
        # Simpler robust method: use socat STDIO UNIX-CONNECT:$SOCK — this sends request and then upgrades to raw stream
        printf "POST /exec/%s/start HTTP/1.1\r\nHost: localhost\r\nConnection: Upgrade\r\nUpgrade: tcp\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" \
            "$exec_id" "$body_len" "$body" \
            | socat - UNIX-CONNECT:"$SOCK"
        # After socat returns, the exec session is finished.
    else
        echo -e "${YELLOW}[WARN] socat not found — falling back to non-interactive start (no TTY).${RESET}"
        api_post "/exec/${exec_id}/start" '{"Detach":false,"Tty":false}'
        echo -e "${YELLOW}[*] To get interactive shells install socat and re-run the command.${RESET}"
    fi
}

cmd_switch() {
    # switch <container> -> interactive shell via exec into /bin/sh
    local container="$1"
    if [[ -z "$container" ]]; then
        echo -e "${RED}[ERR] switch requires container id or name.${RESET}"
        exit 10
    fi
    cmd_exec_interactive "$container" /bin/sh -i
}

cmd_help() {
    cat <<EOF
${CYAN}Socket Hopper — usage${RESET}

$0 <command> [args...]

Commands:
  list
        List all containers (like docker ps -a)

  run <image> [--name NAME] [--detach] -- <cmd...>
        Create and start a container from IMAGE. If --detach provided, returns after start.
        Example: $0 run alpine --name test -- sleep 999

  exec <container> -- <cmd...>
        Run <cmd...> in <container> (non-interactive). Prints stdout/stderr.

  switch <container>
        Attach an interactive TTY shell (/bin/sh) into the container.
        Requires ${CYAN}socat${RESET} for full interactive terminal.

  help
        Show this help.

Notes:
  - This script talks to Docker via $SOCK only.
  - For interactive attach (switch), install 'socat' and 'jq' for nicer output.
  - This script intentionally does NOT attempt privilege escalation or host escapes.

EOF
}

# ----------------------------
# Main
# ----------------------------
if [[ $# -lt 1 ]]; then
    cmd_help
    exit 0
fi

case "$1" in
    list) shift; cmd_list "$@";;
    run) shift; cmd_run "$@";;
    exec) shift; cmd_exec_noninteractive "$@";;
    switch) shift; cmd_switch "$@";;
    help|-h|--help) cmd_help;;
    *) echo -e "${RED}[ERR] Unknown command: $1${RESET}"; cmd_help; exit 11;;
esac
