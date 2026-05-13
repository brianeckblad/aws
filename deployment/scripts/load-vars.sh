#!/usr/bin/env bash
# load-vars.sh — Load deployment variables into the current shell
# Supported shells: bash, zsh
#
# Usage (MUST be sourced, not executed):
#   cd deployment
#   source scripts/load-vars.sh
#
# Exports:
#   host_name    — server name (drives all AWS resource names)
#   aws_region   — AWS region
#   admin_user   — SSH login user on the EC2 instance
#   server_ip    — public IP (only if a running instance is found)

# ── Guard: must be sourced ────────────────────────────────────────────────────
_is_sourced=false
if [ -n "$BASH_VERSION" ] && [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    _is_sourced=true
fi
if [ -n "$ZSH_VERSION" ] && [[ "$ZSH_EVAL_CONTEXT" == *:file* ]]; then
    _is_sourced=true
fi

if [ "$_is_sourced" = false ]; then
    echo "❌  This script must be sourced, not executed:"
    echo "    source scripts/load-vars.sh"
    exit 1
fi

# ── Resolve paths (works regardless of cwd) ──────────────────────────────────
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
_DEPLOYMENT_DIR="$(cd "$_SCRIPT_DIR/.." && pwd)"
_GROUP_VARS="$_DEPLOYMENT_DIR/group_vars/vault.yml"
_INVENTORY="$_DEPLOYMENT_DIR/inventories/hosts.yml"

# ── Colors ────────────────────────────────────────────────────────────────────
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_RED='\033[0;31m'
_BLUE='\033[0;34m'
_NC='\033[0m'

# ── Check vault exists ────────────────────────────────────────────────────────
if [ ! -f "$_GROUP_VARS" ]; then
    echo -e "${_RED}❌  group_vars/vault.yml not found.${_NC}"
    echo "    Run: ./scripts/local-dev-setup.sh"
    return 1
fi

# ── Helper: read a single key from vault (handles encrypted + plain) ──────────
_vault_get() {
    local key="$1"
    local raw=""

    if head -1 "$_GROUP_VARS" 2>/dev/null | grep -q "ANSIBLE_VAULT"; then
        # Encrypted vault
        if [ ! -f "$HOME/.vault_pass" ]; then
            echo -e "${_RED}❌  Vault is encrypted but ~/.vault_pass not found.${_NC}" >&2
            echo "    Create it:  echo 'your-password' > ~/.vault_pass && chmod 600 ~/.vault_pass" >&2
            return 1
        fi
        raw=$(ansible-vault view "$_GROUP_VARS" \
            --vault-password-file "$HOME/.vault_pass" 2>/dev/null \
            | grep "^${key}:")
    else
        raw=$(grep "^${key}:" "$_GROUP_VARS" | head -1)
    fi

    # Use Python to safely extract: strip quotes, inline comments, whitespace
    echo "$raw" | python3 -c "
import sys, re
line = sys.stdin.read().strip()
m = re.match(r'^[^:]+:\s*(.*)', line)
if not m:
    sys.exit(0)
val = m.group(1).strip()
# strip inline comment (but not inside quotes)
val = re.sub(r'\s+#.*$', '', val)
# strip surrounding quotes
val = val.strip('\"').strip(\"'\")
print(val)
" 2>/dev/null
}

# ── Load core vars from vault ─────────────────────────────────────────────────
echo ""
echo -e "${_BLUE}Loading deployment variables...${_NC}"
echo ""

export host_name
export aws_region
export admin_user

host_name=$(_vault_get "host_name")
aws_region=$(_vault_get "aws_region")
admin_user=$(_vault_get "admin_user")

if [ -z "$host_name" ] || [ -z "$aws_region" ] || [ -z "$admin_user" ]; then
    echo -e "${_RED}❌  Could not read one or more variables from vault.yml.${_NC}"
    echo "    Ensure host_name, aws_region, and admin_user are set."
    return 1
fi

# ── Optionally load server IP ─────────────────────────────────────────────────
export server_ip=""

if [ -f "$_INVENTORY" ] && grep -q "ansible_host:" "$_INVENTORY" 2>/dev/null; then
    _detected_ip=$(grep "ansible_host:" "$_INVENTORY" \
        | head -1 \
        | sed 's/.*ansible_host:[[:space:]]*//' \
        | tr -d '[:space:]')

    # Skip localhost/127.0.0.1 — that is the reset placeholder written by
    # terminate-ec2-instance.yml, not a real server IP.
    if [ -n "$_detected_ip" ] && \
       [ "$_detected_ip" != "localhost" ] && \
       [ "$_detected_ip" != "127.0.0.1" ]; then
        echo "Found existing server in inventory:"
        echo "  IP: $_detected_ip"
        echo ""
        printf "Load this IP into the shell? [Y/n]: "
        read -r _choice < /dev/tty
        _choice="${_choice:-y}"

        if [[ "$_choice" =~ ^[Yy]$ ]]; then
            server_ip="$_detected_ip"
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${_GREEN}✅  Variables loaded:${_NC}"
echo -e "  ${_YELLOW}host_name${_NC}   = $host_name"
echo -e "  ${_YELLOW}aws_region${_NC}  = $aws_region"
echo -e "  ${_YELLOW}admin_user${_NC}  = $admin_user"
if [ -n "$server_ip" ]; then
    echo -e "  ${_YELLOW}server_ip${_NC}   = $server_ip"
fi
echo ""

# ── Cleanup private vars ──────────────────────────────────────────────────────
unset _SCRIPT_DIR _DEPLOYMENT_DIR _GROUP_VARS _INVENTORY
unset _GREEN _YELLOW _RED _BLUE _NC
unset _is_sourced _detected_ip _choice
unset -f _vault_get

