#!/usr/bin/env bash
# ================================================
#   Docker Socket Information Gatherer (Read-Only)
# ================================================
#   Uses only GET requests over unix socket
#   No exploitation - pure information collection
# ================================================

SOCK="/var/run/docker.sock"
CURL="curl --silent --unix-socket $SOCK"

# ------ Colors ------
H1="\033[1;36m"   # Cyan
H2="\033[1;35m"   # Purple
OK="\033[1;32m"   # Green
WARN="\033[1;33m" # Yellow
RST="\033[0m"

# ------ Styling ------
divider() { printf "${H2}------------------------------------------------------------${RST}\n"; }
title() { printf "\n${H1}[*] $1${RST}\n"; }

# ------ Check Socket ------
if [[ ! -S "$SOCK" ]]; then
  echo -e "${WARN}[!] Docker socket not found at $SOCK${RST}"
  exit 1
fi

echo -e "${H1}>>> Docker Socket Information Dump <<<${RST}"
divider

# ============================================================
# 1) BASIC DOCKER ENGINE INFO
# ============================================================
title "Docker Engine Version"
/bin/echo -e "$($CURL /version | jq)"

divider

title "Docker System Info"
/bin/echo -e "$($CURL /info | jq)"

divider

# ============================================================
# 2) LIST CONTAINERS + DETAILS
# ============================================================
title "Container List"
/bin/echo -e "$($CURL /containers/json?all=true | jq)"

divider

title "Per-Container Detailed Info"
containers=$( $CURL /containers/json | jq -r '.[].Id' )

for id in $containers; do
    echo -e "${OK}[+] Container: $id${RST}"
    $CURL /containers/$id/json | jq
    divider
done

# ============================================================
# 3) IMAGES
# ============================================================
title "Docker Images"
/bin/echo -e "$($CURL /images/json | jq)"

divider

title "Detailed Image Metadata"
images=$( $CURL /images/json | jq -r '.[].Id' )
for img in $images; do
    echo -e "${OK}[+] Image: $img${RST}"
    $CURL /images/$img/json | jq
    divider
done

# ============================================================
# 4) NETWORKS
# ============================================================
title "Networks"
/bin/echo -e "$($CURL /networks | jq)"

divider

# ============================================================
# 5) VOLUMES
# ============================================================
title "Volumes"
/bin/echo -e "$($CURL /volumes | jq)"

divider

# ============================================================
# 6) CONTAINER ENV VARS / CONFIG / MOUNTS
# ============================================================
title "Container ENV, Mounts, Config"

for id in $containers; do
    echo -e "${OK}[+] Container: $id${RST}"
    $CURL /containers/$id/json | jq '{Name: .Name, Config: .Config.Env, Mounts: .Mounts}'
    divider
done

# ============================================================
# 7) CONTAINER LOGS (last 50 lines)
# ============================================================
title "Container Logs (last 50 lines)"

for id in $containers; do
    echo -e "${OK}[+] Logs for $id${RST}"
    $CURL "/containers/$id/logs?stdout=true&stderr=true&tail=50"
    divider
done

echo -e "${H1}>>> Collection Complete <<<${RST}"
