#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE_DIR/themes/theme.sh"

base64_cleaner() {
    local input="$1"
    local data=""

    # ------------------------------
    # Read file OR raw string input
    # ------------------------------
    if [[ -f "$input" ]]; then
        data="$(cat "$input")"
    else
        data="$input"
    fi

    

    #data="$(printf "%s" "$data" | tr -d '\000-\011\013\014\016-\037\177')"

   
    # Keep ONLY base64-valid chars
    data="$(printf "%s" "$data" | tr -cd 'A-Za-z0-9+/=')"
    # Optional: show raw input

    BANNED_WORDS=("BEGINEXTRACT" "ENDEXTRACT")

    for bad in "${BANNED_WORDS[@]}"; do
        data="${data//$bad/}"
    done
    # Output cleaned base64
    printf "%s" "$data"
}

