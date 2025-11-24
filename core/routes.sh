#!/usr/bin/env bash

# Base directory (project root)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_FILE="$BASE_DIR/themes/theme.sh"
ROUTES_FILE="$BASE_DIR/config/routes.conf"


if [[ ! -f "$ROUTES_FILE" ]]; then
    error "Missing routing table: $ROUTES_FILE"
    hint "Please run: make install"
    hint "Or:   ./start.sh --reset-modules"
    exit 1
fi

# Load theme
[[ -f "$THEME_FILE" ]] && source "$THEME_FILE"
if [[ ! -f "$THEME_FILE" ]]; then
    error " Missing theme script: $THEME_FILE"
    hint " verify that the theme.sh script exists."
    exit 1
fi

# Empty arrays
MODULES=()
AUTO_MODE=()
EXPLOITS_ROUTES=()

##############################################
# LOAD ROUTES FROM config/routes.conf
##############################################
load_routes() {
    while read -r TYPE NAME ROUTE; do

        # Skip empty lines or comments
        [[ "$TYPE" == "" || "$TYPE" =~ ^# ]] && continue

        case "$TYPE" in
            MODULE)
                MODULES+=("$NAME:$ROUTE")
                ;;
            AUTO)
                AUTO_MODE+=("$NAME:$ROUTE")
                ;;
            XPL)
                EXPLOITS_ROUTES+=("$NAME:$ROUTE")
                ;;
        esac

    done < "$ROUTES_FILE"

    # Merge into ROUTES array (must be done AFTER loading)
    ROUTES=("${MODULES[@]}" "${EXPLOITS_ROUTES[@]}" "${AUTO_MODE[@]}")
}

##############################################
# Resolve route by key
##############################################
resolve_route() {
    local name="$1"

    for entry in "${ROUTES[@]}"; do
        key="${entry%%:*}"
        value="${entry#*:}"

        if [[ "$key" = "$name" ]]; then
            # Build candidate path and canonicalize when possible
            local candidate="$BASE_DIR/$value"
            local resolved=""

            if command -v realpath >/dev/null 2>&1; then
                resolved=$(realpath -m -- "$candidate" 2>/dev/null || true)
            elif command -v readlink >/dev/null 2>&1; then
                resolved=$(readlink -f -- "$candidate" 2>/dev/null || true)
            else
                resolved="$candidate"
            fi

            # Ensure resolved path is inside BASE_DIR and points to a regular file
            if [[ -n "$resolved" && "$resolved" == "$BASE_DIR"* && -f "$resolved" ]]; then
                echo "$resolved"
                return 0
            else
                # If validation fails, skip this entry
                continue
            fi
        fi
    done

    return 1
}

# Auto-load the config when sourced
load_routes
