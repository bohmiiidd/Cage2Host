#!/usr/bin/env bash
# Build self-extracting archive for Escaper tool

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$BASE_DIR/build/bin/escaper"
PAYLOAD="$BASE_DIR/build/payload.tar.gz"

echo "[*] Packaging project..."
mkdir -p "$(dirname "$PAYLOAD")"
tar -czf "$PAYLOAD" bin/ core/ modules/ themes/ config/ utility/ start.sh

cat << 'EOF' > "$OUT"
#!/usr/bin/env bash
# Self-extracting container archive (generated)

set -euo pipefail

# Create a safe temp dir and ensure cleanup on EXIT
WORKDIR=""
cleanup() {
	if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
		rm -rf -- "$WORKDIR" || true
	fi
}
trap cleanup EXIT

# Create temp dir (portable fallback)
WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d /tmp/escaper.XXXX)

ARCHIVE_LINE=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0; }' "$0")

tail -n +$ARCHIVE_LINE "$0" | base64 -d | tar -xz -C "$WORKDIR"

cd "$WORKDIR"
bash ./start.sh "$@"
exit 0

__ARCHIVE_BELOW__
EOF

# Append the archive base64-encoded
base64 "$PAYLOAD" >> "$OUT"

chmod 0755 "$OUT"
echo "[+] Built: $OUT (single executable)"
