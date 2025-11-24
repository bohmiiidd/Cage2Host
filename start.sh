#!/usr/bin/env bash

set -euo pipefail

# --------------------------------------------------
# Resolve project root
# --------------------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAIN="$BASE_DIR/core/main.sh"
UTILITY="$BASE_DIR/utility/utility.sh"

# Colors
RED="\033[1;31m"
GRN="\033[1;32m"
YLW="\033[1;33m"
RST="\033[0m"
ORG="\033[1;33m"

error()   { echo -e "${RED}[✖ ERROR]${RST} $1"; }
success() { echo -e "${GRN}[✔ OK]${RST} $1"; }
info()    { echo -e "${YLW}[ℹ INFO]${RST} $1"; }
warning() { echo -e "${ORG}[⚠ WARNING]${RST} $1"; }


# --------------------------------------------------
# HELP MENU
# --------------------------------------------------
show_help() {
    cat <<EOF
Usage:
  start.sh [MODE] [OPTIONS]

Modes:
  --random-mode           Run the core exploitation engine (core/main.sh)
  --utility-mode          Launch utility tools (utility/utility.sh)

Examples:
  start.sh --random-mode 
  start.sh --utility-mode --vuln socket --cmd "id"

EOF
}





# --------------------------------------------------
# Parse the first required argument (mode)
# --------------------------------------------------
if [[ $# -lt 1 ]]; then 
    show_help
    exit 1
fi

MODE="$1"
shift || true  # remove MODE from the argument list

# --------------------------------------------------
# Validate mode
# --------------------------------------------------

case "$MODE" in

    --random-mode)
        info "Launching RANDOM MODE (core/main.sh)"
        if [[ ! -x "$MAIN" ]]; then
            error "main.sh not found or not executable: $MAIN"
            exit 1
        fi
        "$MAIN" "$@"   # forward remaining args
        ;;

    --utility-mode)
        info "Launching UTILITY MODE (utility/utility.sh)"
        if [[ ! -x "$UTILITY" ]]; then
            error "utility.sh not found or not executable: $UTILITY"
            exit 1
        fi
        "$UTILITY" "$@"   # forward all args
        ;;

    -h|--help)
        show_help
        exit 0
        ;;

    *)
        error "Unknown mode: $MODE"
        show_help
        exit 1
        ;;
esac