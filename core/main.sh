#!/usr/bin/env bash

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/core/routes.sh"
source "$BASE_DIR/themes/theme.sh"

banner

print_help() {
    matrix 0.01 
    echo "Usage:"
    echo "  --reset-modules"
    echo "  --list-modules"
    echo "  --list-exploits"
    echo "  --list-all"
    echo "  --auto"
    echo "  --module <module-ID>"
    echo "  --exploit <exploit-ID> --confirm"
}
case "$1" in
        --list-all)
        info "loading modules/exploits from: $BASE_DIR/config/routes.conf"
        if [[ ${#MODULES[@]} -eq 0 ]]; then
            error "No modules defined."
        else
            hint "Using grep might help to find MOD-ID |./start.sh --list-modules | grep <keyword> to search"
            info "Available Modules:"
            for entry in "${MODULES[@]}"; do
                key="${entry%%:*}"
                val="${entry#*:}"
                echo "$key : $val"
            done
        fi
        echo "-----------------------------------"
        if [[ ${#EXPLOITS_ROUTES[@]} -eq 0 ]]; then
            error "No exploits defined."
        else
            info "Available Exploits:"
            for entry in "${EXPLOITS_ROUTES[@]}"; do
                key="${entry%%:*}"
                val="${entry#*:}"
                echo "$key : $val"
            done
        fi
        ;;
        --reset-modules)
        info "loading modules/exploits from: $BASE_DIR/config/routes.conf"
        BUILD_SCRIPT="$BASE_DIR/core/build-routes.sh"

        if [[ ! -f "$BUILD_SCRIPT" ]]; then
            error "Missing: $BUILD_SCRIPT"
            warning "Cannot install modules because build-routes.sh does not exist."
            exit 1
        fi

        info "building..."
        bash "$BUILD_SCRIPT"

        if [[ $? -ne 0 ]]; then
            error "Module installation failed."
            exit 1
        fi

        success "Modules successfully installed."
        ;;



    --utility-mode)
        shift
        "$BASE_DIR/utility/utility.sh" "$@"
        exit 0
        ;;
           
    --list-modules)
        info "loading modules/exploits from: $BASE_DIR/config/routes.conf"
        if [[ ${#MODULES[@]} -eq 0 ]]; then
            error "No modules defined."
            
            exit 0
        fi
        hint "Using grep might help to find MOD-ID |./start.sh --list-exploits | grep <keyword> to search"
        info "Available Modules:"
        for entry in "${MODULES[@]}"; do
            key="${entry%%:*}"
            val="${entry#*:}"
            echo "$key : $val"
        done
        ;;

    --list-exploits)
    info "loading modules/exploits from: $BASE_DIR/config/routes.conf"
        if [[ ${#EXPLOITS_ROUTES[@]} -eq 0 ]]; then
            error "No exploits defined." 
            exit 0
        fi
        hint "Using grep might help to find XPL-ID |./start.sh --list-exploits | grep <keyword> to search"
        for entry in "${EXPLOITS_ROUTES[@]}"; do
            key="${entry%%:*}"
            val="${entry#*:}"
            echo "$key : $val"
        done
        ;;

    --auto)
        info "loading auto scripts   from: $BASE_DIR/config/routes.conf"
        info "Executing AUTO_MODE modules... from $BASE_DIR/modules/auto-mode/"
        auto-banner
        if [[ ${#AUTO_MODE[@]} -eq 0 ]]; then
            error "No AUTO_MODE modules defined."
            exit 0
        fi
        for entry in "${AUTO_MODE[@]}"; do
            key="${entry%%:*}"
            script="${entry#*:}"
            bash "$BASE_DIR/$script"
        done
        ;;

    --module)
        if [[ -z "$2" ]]; then
            error "Error: missing module name"
            exit 1
        fi
        route=$(resolve_route "$2") || { error "Module ID:$2 Not Found!"; exit 1; }
        #route=$(resolve_route "$2" | xargs) || { error "Exploit not found"; exit 1; }
        #echo "PATH:$route" && cat -A < "$route"
        bash "$route" "${@:3}"
        ;;

    --exploit)
        if [[ -z "$2" ]]; then
            error "Error: missing exploit ID"
            exit 1
        fi
        if [[ "$3" != "--confirm" ]]; then
            warning "Error: exploit execution requires --confirm flag"
            exit 1
        fi
        route=$(resolve_route "$2") || { error "Exploit not found"; exit 1; }
        printf '%q\n' "$route"
        if ! bash "$route" "${@:4}"; then
            error "Exploit '$2' failed during execution."
            warning "Check the exploit file for syntax errors or missing paths."
            exit 1
        fi

        ;;

    *)
        if [[ -n "$1" ]]; then
            error "Cannot found argument: $1 "
            print_help
            exit 1
        fi
        
        print_help 
        ;;
esac
