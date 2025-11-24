#!/bin/bash
echo "=== UID / GID Map in This Namespace ==="
echo "UID map:"
cat /proc/self/uid_map
echo "GID map:"
cat /proc/self/gid_map

# Check if 0 maps to 0:
if grep -q "^0 *0 *" /proc/self/uid_map; then
  echo "[!] UID 0 inside maps to UID 0 on host → possible real root"
else
  echo "[+] UID 0 does not map to host root"
fi
