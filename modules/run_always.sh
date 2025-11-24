#!/usr/bin/env bash
set -euo pipefail

# Anchor to project root
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Require a file argument
if [[ $# -lt 1 ]]; then
    echo "[ERROR] No file provided"
    exit 1
fi

USER_FILE="$1"
TARGET_FILE="$BASE_DIR/$USER_FILE"

# Validate existence
if [[ ! -f "$TARGET_FILE" ]]; then
    echo "[ERROR] File not found: $USER_FILE"
    echo "[DEBUG] Looked in: $TARGET_FILE"
    exit 1
fi

# Ensure executable bit so kernel can load it
if [[ ! -x "$TARGET_FILE" ]]; then
    chmod +x "$TARGET_FILE"
fi

echo "[INFO] Running file using its shebang → $TARGET_FILE"

# Capture the first line to inspect the shebang
FIRST_LINE="$(head -n 1 "$TARGET_FILE")"

# Check missing shebang
if [[ ! "$FIRST_LINE" =~ ^#! ]]; then
    echo "[ERROR] Missing shebang."
    echo "The script cannot be auto-executed without specifying interpreter."
    echo "Add something like:"
    echo "  #!/usr/bin/env python3"
    echo "  #!/usr/bin/env bash"
    exit 1
fi

# Extract interpreter (everything after #!)
INTERPRETER="$(echo "$FIRST_LINE" | cut -c3- | awk '{print $1}')"

# Validate interpreter availability
if ! command -v "$INTERPRETER" >/dev/null 2>&1; then
    echo "[ERROR] Invalid or missing interpreter: $INTERPRETER"
    echo "Please install it or update the shebang."
    exit 1
fi

# Execute using shebang
"$TARGET_FILE" || {
    echo "[ERROR] Script execution failed."
    exit 1
}
