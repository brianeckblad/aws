# Prerequisites

Set up your AWS account, local tools, and deployment configuration before provisioning the server.

---

## Table of Contents

1. [AWS Account Setup](#aws-account-setup)
2. [Local Tools](#local-tools)
3. [Install Deployment Requirements](#install-deployment-requirements)
4. [Create Deployment Configuration](#create-deployment-configuration)
5. [Create IAM Deployer User](#create-iam-deployer-user)
6. [Verification Checklist](#verification-checklist)

---

## AWS Account Setup

**Already have an AWS account?** Skip to [Local Tools](#local-tools).
1. Go to [aws.amazon.com](https://aws.amazon.com) and create an account.
2. Note your **Account ID** — visible at [Console → Account](https://console.aws.amazon.com/billing/home#/account).
3. Create a temporary root access key:
   - Sign in → click your name (top-right) → **Security credentials**
   - Under **Access keys** → **Create access key**
   - Save the Key ID and Secret — needed in the next step

> ⚠️ Never use the root account for day-to-day work. You will replace these credentials with a scoped deployer user in [Create IAM Deployer User](#create-iam-deployer-user).

### Configure AWS CLI with root credentials (temporary)

```bash
brew install awscli      # macOS; use apt or the official installer on Linux

aws configure
# Enter root key ID, secret, region (e.g. us-east-2), output format (json)

# Verify
aws sts get-caller-identity
# Shows account ID and root ARN
```

---

## Local Tools

| Tool | Purpose | Min version |
|------|---------|------------|
| Python | Runtime for Ansible and scripts | 3.8+ |
| Ansible | Automation | 2.12+ |
| AWS CLI | AWS operations | 2.x |
| Git | Version control | Latest |
| SSH | Connect to EC2 | OpenSSH |

### Install

**macOS (Homebrew):**
```bash
brew install python3 ansible awscli git openssh
```

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y python3 python3-pip git openssh-client awscli
pip3 install ansible
```

### Verify

```bash
python3 --version      # 3.8+
ansible --version      # 2.12+
aws --version          # 2.x
git --version
ssh -V
```

---

## Install Deployment Requirements

```bash
# From repo root
# Python packages (boto3, botocore, etc.)
pip3 install -r requirements.txt

# Ansible collections (amazon.aws, community.general)
ansible-galaxy collection install -r requirements.yml --upgrade
```

---

## Create Deployment Configuration

All configuration lives in a single encrypted vault file.

### Step 1: Scaffold files

```bash
cd deployment
./scripts/local-dev-setup.sh
```

This script creates `group_vars/vault.yml` (from the template) and `inventories/hosts.yml`.
Run with `-merge` if you have an existing vault from a previous deployment.

### Step 2: Edit the vault

```bash
nano group_vars/vault.yml
```

**Server-level variables to set** (these drive everything in this repo):

| Variable | Description | Example |
|----------|-------------|---------|
| `host_name` | Short name for the server — drives EC2 tag, SG, IAM role, SSH key | `web01` |
| `admin_user` | SSH login user (Ubuntu default) | `ubuntu` |
| `aws_region` | AWS region for all resources | `us-east-2` |
| `aws_root_account_email` | For EC2 serial console policy | `you@example.com` |
| `ec2_instance_type` | Instance size | `t3.small` |
| `apps_root` | EBS mount point — parent dir for all apps | `/opt/apps` |
| `logs_root` | Parent dir for all app logs | `/var/log/apps` |
| `ebs_volume_size` | Data EBS size in GB | `100` |

Leave all `# APPLICATION` section variables at their defaults — those are used by each app's own deployment repo, not this one.

### Step 3: Create a vault password file

```bash
echo "your-secure-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

Store this password in a password manager. If you lose it you cannot decrypt the vault.

### Step 4: Encrypt the vault

```bash
ansible-vault encrypt group_vars/vault.yml --vault-password-file ~/.vault_pass

# Confirm encryption
head -1 group_vars/vault.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256
```

### View or edit later

```bash
ansible-vault view group_vars/vault.yml --vault-password-file ~/.vault_pass
ansible-vault edit group_vars/vault.yml --vault-password-file ~/.vault_pass
```

---

## Create IAM Deployer User

Replace temporary root credentials with a scoped IAM user.

The deployer user needs:
- `AmazonEC2FullAccess`
- `AmazonS3FullAccess`
- `IAMFullAccess`
- `SecretsManagerReadWrite`
- `CloudWatchLogsFullAccess`

### Option A: AWS Console

1. Go to [IAM → Users → Create user](https://console.aws.amazon.com/iam/home#/users)
2. User name: `{{ host_name }}-deployer`
3. Attach the 5 managed policies listed above
4. Create an **Access key** (Programmatic access) and save the key + secret

### Option B: AWS CLI (with root credentials)

```bash
USER="{{ host_name }}-deployer"   # from vault.yml — host_name

aws iam create-user --user-name $USER
for POLICY in AmazonEC2FullAccess AmazonS3FullAccess IAMFullAccess \
              SecretsManagerReadWrite CloudWatchLogsFullAccess; do
  aws iam attach-user-policy \
    --user-name $USER \
    --policy-arn arn:aws:iam::aws:policy/$POLICY
done
aws iam create-access-key --user-name $USER
# Save the AccessKeyId and SecretAccessKey from the output
```

### Option C: Ansible playbook (recommended)

Run once with your temporary root credentials after completing [Create Deployment Configuration](#create-deployment-configuration):

```bash
cd deployment
ansible-playbook playbooks/create-iam-deployer-user.yml \
  --vault-password-file ~/.vault_pass
```

The playbook creates the `{{ host_name }}-deployer` user, attaches all required policies, and prints the access key once. Save it immediately — it is not shown again.

### Switch to deployer credentials

```bash
aws configure
# Enter deployer key ID, secret, same region, json

aws sts get-caller-identity
# ARN should now show: ...user/{{ host_name }}-deployer
```

### Delete the root access key

1. Sign in to the console as root
2. Click your name → **Security credentials** → **Access keys** → **Delete**

---

## Verification Checklist

Run these before provisioning. Every command should succeed.

```bash
# AWS CLI uses deployer, not root
aws sts get-caller-identity

# Ansible is installed
ansible --version

# Vault is encrypted
head -1 deployment/group_vars/vault.yml
# → $ANSIBLE_VAULT;1.1;AES256

# Vault password file exists with correct permissions
ls -la ~/.vault_pass
# → -rw------- (600)

# Vault can be decrypted
ansible-vault view deployment/group_vars/vault.yml --vault-password-file ~/.vault_pass | grep host_name
```

---

## Next step

Choose your deployment path:

| I want to… | Guide |
|------------|-------|
| Get up and running as fast as possible | → [Quick Start](QUICKSTART.md) — provision the server with a single command |
| Understand each step or run playbooks individually | → [Manual Deployment](MANUAL_DEPLOYMENT.md) — step-by-step walkthrough |
