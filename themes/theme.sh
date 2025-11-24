#!/usr/bin/env bash
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$BASE_DIR/config/fun.conf"
# ===== COLORS =====
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
MAGENTA="\033[35m"
WHITE="\033[37m"

# ===== BANNER =====
banner() {
    echo -e "${BOLD}${CYAN}
╔═╗┌─┐┌─┐┌─┐  ╦ ╦┌─┐┌─┐┌┬┐
║  ├─┤│ ┬├┤ 2 ╠═╣│ │└─┐ │ 
╚═╝┴ ┴└─┘└─┘  ╩ ╩└─┘└─┘ ┴               
${RESET}"
}



# ===== LOGGING =====
error() {
    echo -e "${RED}[✖ ERROR]${RESET} $1"
}

info() {
    echo -e "${BLUE}[ℹ INFO]${RESET} $1"
}

warning() {
    echo -e "${YELLOW}[⚠ WARN]${RESET} $1"
}

success() {
    echo -e "${GREEN}[✔ SUCCESS]${RESET} $1"
}

hint() {
    echo -e "${MAGENTA}[💡 HINT]${RESET} $1"
}

# ===== MATRIX EFFECT =====
matrix() {
    local speed="${1:-0.02}"
    local line char

    # Use $CONFIG_FILE consistently!
    if [[ -f "$CONFIG_FILE" ]]; then
        line=$(shuf -n 1 "$CONFIG_FILE")
    else
        line="Config file of my words is missed but who care? Let's go scaping!"
    fi

    # Print each character in green
    for ((i=0; i<${#line}; i++)); do
        char="${line:i:1}"
        if [[ "$char" != " " ]]; then
            printf "\033[32m%s\033[0m" "$char"
        else
            printf " "
        fi
        sleep "$speed"
    done
    echo
}

# Run it
#matrix 0.01

# ===== DEMO =====
# banner
# info "This is info"
# warning "Be careful!"
# error "Something went wrong"
# success "It worked!"
# hint "Remember to run make install first!"
# matrix "Matrix style text..." 0.01
