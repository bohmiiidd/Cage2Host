#!/usr/bin/env bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES_FILE="$BASE_DIR/config/routes.conf"



# Generate next exploit ID Format: XPL-001
generate_xpl_id() {
    local last_id
    last_id=$(grep "^XPL" "$ROUTES_FILE" | tail -n1 | awk '{print $2}' | sed 's/XPL-//')

    if [[ "$last_id" == "" ]]; then
        echo "XPL-001"
    else
        next=$(printf "%03d" $((10#$last_id + 1)))
        echo "XPL-$next"
    fi
}
# Generate next MODULE ID Format: MOD-001

generate_mod_id() {
    local last_id
    last_id=$(grep "^MODULE" "$ROUTES_FILE" | tail -n1 | awk '{print $2}' | sed 's/MOD-//')

    if [[ "$last_id" == "" ]]; then
        echo "MOD-001"
    else
        next=$(printf "%03d" $((10#$last_id + 1)))
        echo "MOD-$next"
    fi
}



# Scan modules/auto-mode/ for auto scripts
scan_autoScripts() {
    local auto_dir="$BASE_DIR/modules/auto-mode"

    echo "[INFO] Scanning auto-mode/ ..."

    [[ -d "$auto_dir" ]] || { echo "[WARN] no auto-mode directory."; return; }

    while IFS= read -r file; do
        auto_id=$(generate_mod_id)   # <-- FIX: generate new ID for each file
        rel_path="modules/auto-mode/$(basename "$file")"
        echo "AUTO $auto_id $rel_path" >> "$ROUTES_FILE"
        echo "[OK] Added AUTO ($auto_id): $rel_path"
    done < <(
        find "$auto_dir" -maxdepth 1 -type f \
        ! -path "*/bin/*" \
        \( -name "*.sh" -o -name "*.py" -o -name "*.pl" \
        -o -name "*.rb" -o -name "*.php" -o -name "*.js" \
        -o -name "*.go" -o -perm -111 \)
    )
}



scan_modules() {
    echo "[INFO] Scanning modules/ ..."

    # --- 1. Scan top-level scripts directly under modules/ ---
    echo "[INFO] Scanning modules/ for standalone scripts ..."
    while IFS= read -r file; do
        filename=$(basename "$file")

        # Skip bin/ entry if matched by mistake
        [[ "$filename" == "bin" ]] && continue

        module_id=$(generate_mod_id)
        rel_path="modules/$filename"

        echo "MODULE $module_id $rel_path" >> "$ROUTES_FILE"
        echo "[OK] Added MODULE ($module_id): $rel_path"

    done < <(
        find "$BASE_DIR/modules" -maxdepth 1 -type f \
            \( -name "*.sh" -o -name "*.py" -o -name "*.pl" \
            -o -name "*.rb" -o -name "*.php" -o -name "*.js" \
            -o -name "*.go" -o -perm -111 \)
    )


    # --- 2. Scan nested module directories ---
    echo "[INFO] Scanning modules/* directories ..."

    for dir in "$BASE_DIR/modules/"*; do
        [[ -d "$dir" ]] || continue

        module_name=$(basename "$dir")

        # SKIP modules/bin/
        if [[ "$module_name" == "bin" ]]; then
            echo "[SKIP] Ignoring modules/bin/"
            continue
        fi

        # SKIP auto-mode, scanned separately
        if [[ "$module_name" == "auto-mode" ]]; then
            echo "[SKIP] Ignoring modules/auto-mode/ (handled by scan_autoScripts)"
            continue
        fi

        while IFS= read -r file; do
            module_id=$(generate_mod_id)
            rel_path="modules/$module_name/$(basename "$file")"

            echo "MODULE $module_id $rel_path" >> "$ROUTES_FILE"
            echo "[OK] Added MODULE ($module_id): $rel_path"

        done < <(
            find "$dir" -maxdepth 1 -type f \
                \( -name "*.sh" -o -name "*.py" -o -name "*.pl" \
                -o -name "*.rb" -o -name "*.php" -o -name "*.js" \
                -o -name "*.go" -o -perm -111 \)
        )

    done
}




# Scan bin/ for exploits
scan_exploits() {
    echo "[INFO] Scanning bin/ for exploits ..."

    for file in "$BASE_DIR/bin/"*.sh; do
        [[ -f "$file" ]] || continue

        filename=$(basename "$file")
        xpl_id=$(generate_xpl_id)

        echo "XPL $xpl_id bin/$filename" >> "$ROUTES_FILE"
        echo "[OK] Added EXPLOIT: $xpl_id ($filename)"
    done
}



# Write clean header
reset_routes_conf() {
    cat > "$ROUTES_FILE" <<EOF
# Auto-generated routing table
# DO NOT EDIT MANUALLY

EOF
    echo "[INFO] Reset routes.conf"
}



echo "[DONE] Routing table is ready in config/routes.conf"
