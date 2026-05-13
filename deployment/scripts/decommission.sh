#!/bin/bash
#
# Decommission - Resource Discovery and Teardown
# Supported shells: bash, zsh
#
# Discovers ALL AWS resources for this server (EC2, SG, IAM role, SSH key)
# and runs the decommission playbook if any exist.
# Safe to run even after partial teardown or manual EC2 deletion.
#
# Usage:
#   cd deployment
#   ./scripts/decommission.sh

set -e

# ── Shell compatibility ──────────────────────────────────────────────
current_shell=$(ps -p $$ -o comm= 2>/dev/null)
current_shell=$(basename "$current_shell" 2>/dev/null)
current_shell=$(echo "$current_shell" | tr -d '-')
if [[ -z "$current_shell" ]]; then
    current_shell=$(basename "$SHELL" 2>/dev/null)
    current_shell=$(echo "$current_shell" | tr -d '-')
fi
case "$current_shell" in
    bash|zsh) ;;
    *)
        echo "⚠️  Unsupported shell: $current_shell (need bash or zsh)" >&2
        exit 1
        ;;
esac

# ── Resolve paths ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GROUP_VARS_DIR="$DEPLOYMENT_DIR/group_vars"

# ── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Load host_name and aws_region ────────────────────────────────────
if [[ ! -f "$GROUP_VARS_DIR/vault.yml" ]]; then
    echo -e "${RED}ERROR: $GROUP_VARS_DIR/vault.yml not found${NC}"
    echo "Run ./scripts/local-dev-setup.sh first."
    exit 1
fi

_read_vault_key() {
    local key="$1"
    if head -1 "$GROUP_VARS_DIR/vault.yml" 2>/dev/null | grep -q "ANSIBLE_VAULT"; then
        [[ -f "$HOME/.vault_pass" ]] || { echo ""; return; }
        ansible-vault view "$GROUP_VARS_DIR/vault.yml" \
            --vault-password-file "$HOME/.vault_pass" 2>/dev/null \
            | grep -E "^${key}:" | head -1 \
            | sed "s/^${key}:[[:space:]]*//" | sed 's/#.*//' \
            | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'"
    else
        grep -E "^${key}:" "$GROUP_VARS_DIR/vault.yml" | head -1 \
            | sed "s/^${key}:[[:space:]]*//" | sed 's/#.*//' \
            | sed 's/[[:space:]]*$//' | tr -d '"' | tr -d "'"
    fi
}

host_name=$(_read_vault_key "host_name")
if [[ -z "$host_name" ]]; then
    echo -e "${RED}ERROR: host_name not set in vault.yml${NC}"
    exit 1
fi

aws_region=$(_read_vault_key "aws_region")
if [[ -z "$aws_region" ]]; then
    aws_region="us-east-2"
fi

if ! command -v aws &>/dev/null; then
    echo -e "${RED}ERROR: AWS CLI not installed.${NC}"
    exit 1
fi

# ── Discover all resources ───────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            Decommission — Resource Discovery             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Server: $host_name"
echo "  Region: $aws_region"
echo ""
echo "Scanning AWS for resources named '${host_name}-*' ..."
echo ""

found_any=false

# EC2 instance
ec2_json=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$host_name" \
              "Name=instance-state-name,Values=running,stopped,stopping,pending" \
    --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Type:InstanceType}' \
    --region "$aws_region" --output json 2>/dev/null) || ec2_json="[]"

ec2_count=0
if [[ -n "$ec2_json" && "$ec2_json" != "[]" ]]; then
    ec2_count=$(python3 -c "import json; print(len(json.loads('''$ec2_json''')))" 2>/dev/null || echo 0)
fi

if [[ "$ec2_count" -gt 0 ]]; then
    echo -e "  ${GREEN}✓ EC2 instance(s):${NC} $ec2_count found"
    python3 -c "
import json
data = json.loads('''$ec2_json''')
for i in data:
    ip = i.get('IP') or 'no public IP'
    print(f'      {i[\"ID\"]}  {i[\"State\"]:<10s}  {ip:<16s}  {i[\"Type\"]}')
" 2>/dev/null
    found_any=true
else
    echo -e "  ${YELLOW}–  EC2 instance:${NC}     not found (already deleted or never created)"
fi

# Security group
sg_result=$(aws ec2 describe-security-groups \
    --group-names "${host_name}-sg" \
    --region "$aws_region" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null) || sg_result=""

if [[ -n "$sg_result" && "$sg_result" != "None" ]]; then
    echo -e "  ${GREEN}✓ Security group:${NC}    ${host_name}-sg  ($sg_result)"
    found_any=true
else
    echo -e "  ${YELLOW}–  Security group:${NC}   not found"
fi

# IAM role
iam_result=$(aws iam get-role \
    --role-name "${host_name}-ec2-role" \
    --query 'Role.RoleName' \
    --output text 2>/dev/null) || iam_result=""

if [[ -n "$iam_result" && "$iam_result" != "None" ]]; then
    echo -e "  ${GREEN}✓ IAM role:${NC}          ${host_name}-ec2-role"
    found_any=true
else
    echo -e "  ${YELLOW}–  IAM role:${NC}          not found"
fi

# SSH key pair
key_result=$(aws ec2 describe-key-pairs \
    --key-names "${host_name}-key" \
    --region "$aws_region" \
    --query 'KeyPairs[0].KeyName' \
    --output text 2>/dev/null) || key_result=""

if [[ -n "$key_result" && "$key_result" != "None" ]]; then
    echo -e "  ${GREEN}✓ SSH key pair:${NC}      ${host_name}-key"
    found_any=true
else
    echo -e "  ${YELLOW}–  SSH key pair:${NC}      not found"
fi

# EBS data volume
ebs_result=$(aws ec2 describe-volumes \
    --filters "Name=tag:Name,Values=${host_name}-data" \
              "Name=tag:Server,Values=${host_name}" \
    --region "$aws_region" \
    --query 'Volumes[0].{ID:VolumeId,State:State,Size:Size}' \
    --output text 2>/dev/null) || ebs_result=""

if [[ -n "$ebs_result" && "$ebs_result" != "None" ]]; then
    echo -e "  ${GREEN}✓ EBS data volume:${NC}   ${ebs_result}"
    found_any=true
else
    echo -e "  ${YELLOW}–  EBS data volume:${NC}   not found"
fi

# IAM deployer user
deployer_result=$(aws iam get-user \
    --user-name "${host_name}-deployer" \
    --query 'User.UserName' \
    --output text 2>/dev/null) || deployer_result=""

if [[ -n "$deployer_result" && "$deployer_result" != "None" ]]; then
    echo -e "  ${GREEN}✓ IAM deployer user:${NC} ${host_name}-deployer"
    found_any=true
else
    echo -e "  ${YELLOW}–  IAM deployer user:${NC} not found (may have been deleted or not yet created)"
fi

echo ""

# ── Nothing to do ────────────────────────────────────────────────────
if [[ "$found_any" != "true" ]]; then
    echo "  No AWS resources found for '$host_name'. Nothing to decommission."
    echo ""
    exit 0
fi

# ── Confirm before calling the playbook ──────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ⚠️  DESTRUCTIVE OPERATION — ALL DATA WILL BE DELETED   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  All resources listed above will be permanently deleted."
echo ""
printf "  Type the server name to confirm [%s]: " "$host_name"
read -r confirm

if [[ "$confirm" != "$host_name" ]]; then
    echo ""
    echo -e "${RED}Confirmation failed.${NC} You typed '$confirm' but host_name is '$host_name'."
    echo "Run again and type '$host_name' to confirm."
    exit 1
fi

# ── Ask about IAM deployer user credentials (always ask) ─────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  IAM Deployer User: ${host_name}-deployer"
echo "  │"
if [[ -n "$deployer_result" && "$deployer_result" != "None" ]]; then
    echo "  │  ⚠  This user exists. Deleting it will permanently"
    echo "  │     invalidate your current AWS credentials."
else
    echo "  │  The user was not found — it may have already been"
    echo "  │  deleted or was never created."
fi
echo "  └─────────────────────────────────────────────────────────┘"
printf "  Also delete the IAM deployer user and credentials? [y/N]: "
read -r delete_deployer_answer

delete_deployer_user=false
if [[ "$delete_deployer_answer" =~ ^[Yy]$ ]]; then
    delete_deployer_user=true
    echo -e "  ${RED}→ IAM deployer user WILL be deleted.${NC}"
else
    echo -e "  ${GREEN}→ IAM deployer user will be KEPT (skipped).${NC}"
fi

echo ""
echo "Starting decommission..."
echo ""

# ── Run the playbook ─────────────────────────────────────────────────
cd "$DEPLOYMENT_DIR"
ansible-playbook playbooks/decommission.yml \
    --vault-password-file ~/.vault_pass \
    -e "decommission_confirmed=true" \
    -e "delete_deployer_user=${delete_deployer_user}"

