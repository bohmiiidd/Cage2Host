#!/usr/bin/env bash
# ============================================================
#   DOCKER SOCKET HUNTER - ADVANCED DETECTION ENGINE
#   Finds Docker socket even if hidden, renamed, symlinked,
#   re-mounted, bind-mounted, or replaced.
# ============================================================

H1="\033[1;36m"
H2="\033[1;35m"
OK="\033[1;32m"
ER="\033[1;31m"
RST="\033[0m"

echo -e "${H1}>>> Advanced Docker Socket Hunter <<<${RST}"

FOUND_SOCKETS=()

divider() { echo -e "${H2}--------------------------------------------------${RST}"; }

add_socket() {
    local path="$1"
    FOUND_SOCKETS+=("$path")
}

check_socket_valid() {
    local sock="$1"
    local OUT

    OUT=$(curl --silent --max-time 1 --unix-socket "$sock" http://localhost/_ping 2>/dev/null)

    if [[ "$OUT" == "OK" ]]; then
        echo -e "${OK}[+] Valid Docker socket found: $sock${RST}"
        add_socket "$sock"
        return 0
    else
        echo -e "${ER}[-] Invalid socket: $sock${RST}"
        return 1
    fi
}

divider
echo -e "${H1}[*] Stage 1: Check default locations${RST}"
divider

DEFAULTS=(
    "/var/run/docker.sock"
    "/run/docker.sock"
    "/mnt/docker.sock"
    "/host/var/run/docker.sock"
    "/docker.sock"
)

for path in "${DEFAULTS[@]}"; do
    if [[ -S "$path" ]]; then
        echo -e "${OK}[+] Found UNIX socket: $path${RST}"
        check_socket_valid "$path"
    fi
done


divider
echo -e "${H1}[*] Stage 2: Search entire filesystem for *.sock${RST}"
divider

# Fast find for sockets
while IFS= read -r sock; do
    echo -e "${OK}[+] Socket candidate: $sock${RST}"
    check_socket_valid "$sock"
done < <(find / -type s 2>/dev/null)


divider
echo -e "${H1}[*] Stage 3: Inspect /proc for open file descriptors${RST}"
divider

for pid in /proc/[0-9]*; do
    FD_PATH="$pid/fd"
    [[ -d "$FD_PATH" ]] || continue

    while IFS= read -r fd; do
        TARGET=$(readlink "$fd" 2>/dev/null)
        if [[ "$TARGET" == *"docker.sock"* ]]; then
            echo -e "${OK}[+] Found via /proc leakage: $TARGET${RST}"
            REAL=$(realpath "$fd" 2>/dev/null)
            check_socket_valid "$REAL"
        fi
    done < <(find "$FD_PATH" -type l 2>/dev/null)
done


divider
echo -e "${H1}[*] Stage 4: Search mount points (hidden bind mounts)${RST}"
divider

grep -E "docker.sock" /proc/self/mountinfo | while read -r line; do
    MNT=$(echo "$line" | awk '{print $5}')
    if [[ -S "$MNT" ]]; then
        echo -e "${OK}[+] Found via mountinfo: $MNT${RST}"
        check_socket_valid "$MNT"
    fi
done


divider
echo -e "${H1}[*] Stage 5: Look for renamed or disguised sockets${RST}"
divider

# Sockets that are not named docker.sock but point to it
for sock in $(find / -type s 2>/dev/null); do
    TARGET=$(stat -Lc "%N" "$sock" 2>/dev/null)
    if echo "$TARGET" | grep -q "docker"; then
        echo -e "${OK}[+] Suspicious symlink: $sock -> $TARGET${RST}"
        check_socket_valid "$sock"
    fi
done


divider
echo -e "${H1}[*] Summary${RST}"
divider

if [[ ${#FOUND_SOCKETS[@]} -eq 0 ]]; then
    echo -e "${ER}[!] No valid Docker socket found.${RST}"
else
    echo -e "${OK}[+] Valid Docker sockets found:${RST}"
    for s in "${FOUND_SOCKETS[@]}"; do
        echo "  - $s"
    done
fi

echo -e "${H1}>>> Done <<<${RST}"
