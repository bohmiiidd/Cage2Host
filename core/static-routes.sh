#!/usr/bin/env bash

## this script is disabled by default, it creates a static routing table if you prefer that, but normally the script use config/routes.conf as a dynamic routing table 
# is defines static routes for modules, auto-modes, and exploits
## it can be used as a fallback or for testing purposes
## if you want to use it, just source this file instead of routes.sh in main.sh by juste replacing the line:
## source "$BASE_DIR/core/routes.sh" by source "$BASE_DIR/core/static-routes.sh" 
## or simply rename this file to routes.sh and backup the original routes.sh



# Base directory (project root)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$BASE_DIR/themes/theme.sh"


#============================
# Load theme (colors)
#==============================
if [[ -f "$THEME_FILE" ]]; then
    source "$THEME_FILE"
else
    echo "[WARN] theme.sh not found: $THEME_FILE"
fi

# ==========================
#  MODULES ROUTING TABLE
# ==========================
modules=(
  "unix_socket_test:modules/unix-socket/test-connection.sh"
  # add more modules here
)

# ==========================
#  AUTOMATED MODE ROUTES
# ==========================
AUTO_MODE=(
  "unix_socket_test:modules/unix-socket/test-connection.sh"
  # add more automated checks here
)

# ==========================
#  EXPLOIT ROUTING TABLE
# ==========================
EXPLOITS_ROUTES=(
  "XPL-1:bin/test-connection.sh"
  # add more exploits here
)

# Merge all for resolver
ROUTES=(
  "${modules[@]}"
  "${EXPLOITS_ROUTES[@]}"
  "${AUTO_MODE[@]}"
)

# Resolve route by key name
resolve_route() {
  local name="$1"
  for entry in "${ROUTES[@]}"; do
    key="${entry%%:*}"
    value="${entry#*:}"
    if [[ "$key" = "$name" ]]; then
      echo "$BASE_DIR/$value"
      return 0
    fi
  done
  return 1
}
