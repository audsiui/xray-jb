# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular Xray VLESS deployment script that supports both direct connection and Cloudflare Tunnel modes. The script is optimized for Alpine Linux (using OpenRC) while maintaining full compatibility with Debian/Ubuntu/CentOS (using systemd).

**Key design principle**: Modular architecture with separated concerns - library files (`lib/`) provide reusable utilities, core modules (`core/`) implement specific functionality, and `main.sh` serves as the entry point with an interactive menu.

## Architecture

```
jb/
├── main.sh              # Entry point - menu system, loads all modules
├── lib/
│   ├── utils.sh         # Colors, logging functions, global variables, root check, validation, download utilities
│   ├── system.sh        # OS detection (apk/apt/yum), architecture detection
│   └── service.sh       # Service setup for systemd and OpenRC
└── core/
    ├── install_direct.sh   # VLESS + WS direct connection mode
    ├── install_tunnel.sh   # VLESS + WS + CF Tunnel mode (localhost only)
    └── uninstall.sh        # Removes all services and files
```

### Module Loading Order (Critical)

`main.sh` must source files in this order:
1. `lib/utils.sh` - Defines base functions and variables
2. `lib/system.sh` - OS/arch detection, depends on utils
3. `lib/service.sh` - Service management, depends on utils
4. `core/*.sh` - Feature implementations, depend on all libs

### Global Variables (from `lib/utils.sh`)

- `WORK_DIR="/opt/xray-bundle"` - All binaries and configs stored here
- `XRAY_BIN="${WORK_DIR}/xray"`
- `CF_BIN="${WORK_DIR}/cloudflared"`
- `CONFIG_FILE="${WORK_DIR}/config.json"`
- Color codes: `RED`, `GREEN`, `YELLOW`, `CYAN`, `PLAIN`

### Service Architecture

Services are managed through `lib/service.sh:setup_service($name, $cmd, $args)`:
- **systemd**: Creates `/etc/systemd/system/{name}.service` with `Type=simple`, enables auto-start, then restarts
- **OpenRC (Alpine)**: Creates `/etc/init.d/{name}` openrc-run script, adds to default runlevel, then restarts

Two service prefixes are used to avoid conflicts:
- `xray-d` - Direct mode Xray service
- `xray-t` - Tunnel mode Xray service
- `cloudflared-t` - Cloudflare Tunnel service

### Installation Modes

**Direct Mode** (`install_direct.sh`):
- Downloads and installs Xray only
- Configures Xray to listen on `0.0.0.0:PORT`
- Outputs `vless://` link with public IP

**Tunnel Mode** (`install_tunnel.sh`):
- Downloads Xray + cloudflared
- Configures Xray to listen on `0.0.0.0:PORT`
- Requires Cloudflare Tunnel token (stored in `/opt/xray-bundle/.cf_token` with 600 permissions)
- Creates wrapper script `/tmp/cloudflared_token.sh` to pass token via environment variable
- Outputs `vless://` link with CF domain

### Error Handling and Rollback Pattern

Both install modes use a consistent error handling pattern:
1. Downloads use `download_file()` with 3 retry attempts and user confirmation on failure
2. Each critical step has failure checks with `rollback_install()` prompts
3. Service startup is verified with `verify_service_running()` (10 second timeout)
4. Rollback removes services, reloads daemon, and deletes `$WORK_DIR`

## Running the Script

```bash
# Interactive menu
bash main.sh

# Or run via curl (one-liner)
bash <(curl -sL https://raw.githubusercontent.com/audsiui/xray-jb/main/main.sh)
```

## Service Management Commands

**Systemd (Debian/Ubuntu/CentOS)**:
```bash
systemctl start/stop/restart/status xray-d   # Direct mode
systemctl start/stop/restart/status xray-t   # Tunnel mode Xray
systemctl start/stop/restart/status cloudflared-t  # CF Tunnel
```

**OpenRC (Alpine)**:
```bash
rc-service xray-d start/stop/restart/status
rc-service xray-t start/stop/restart/status
rc-service cloudflared-t start/stop/restart/status
```

## Configuration Files

- Xray config: `/opt/xray-bundle/config.json`
- Binary location: `/opt/xray-bundle/xray` or `/opt/xray-bundle/cloudflared`
- CF Token: `/opt/xray-bundle/.cf_token` (tunnel mode only, 600 permissions)
- Domain info: `/opt/xray-bundle/.domain_info` (tunnel mode only, 600 permissions)
- CF wrapper: `/tmp/cloudflared_token.sh` (tunnel mode only)

## OS Detection Details

The script in `lib/system.sh` detects:
1. **Package Manager**: Sets `PM` variable (`apk`, `apt`, `yum`)
2. **OS Type**: Sets `OS_TYPE` (`alpine` or `standard`)
3. **Architecture**: Sets download URLs for x86_64 and aarch64

For Alpine, additional packages are installed for compatibility: `bash curl unzip ca-certificates libc6-compat gcompat coreutils`

## Development Notes

- All library files must be sourced before core modules
- Never hardcode paths - use global variables from `utils.sh`
- Always call `check_root` before any privileged operations
- Use `log_info`, `log_warn`, `log_err` for output (colors handled)
- The script creates dynamic WebSocket paths (4 random chars) to avoid fingerprinting
- Input validation uses `trim()`, `validate_port()`, and `validate_domain()` from `utils.sh`
- Public IP detection in `get_public_ip()` falls back through multiple methods: IPv4 API, IPv6 API, then `ip addr` command
