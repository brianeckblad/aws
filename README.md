# aws

**Ansible automation for provisioning, hardening, and managing shared EC2 servers on AWS.**

This repo handles server infrastructure only. Application deployments (SSL certificates, supervisor programs, S3 buckets, Secrets Manager entries) are managed from each app's own repo.

---

## What It Provisions

```
EC2 (shared server — Ubuntu 24.04 LTS)
├── supervisor     shared process manager
├── fail2ban       brute-force protection
├── UFW            firewall (default deny; 22/80/443 open)
├── /opt/apps/     EBS data volume — survives instance termination
└── /var/log/apps/ shared log root for all apps
```

| AWS Resource | Name | Notes |
|---|---|---|
| EC2 instance | `{host_name}` | Ubuntu 24.04 LTS |
| Security group | `{host_name}-sg` | Ports 22, 80, 443 |
| IAM role | `{host_name}-ec2-role` | S3, Secrets Manager, CloudWatch, SNS, SSM |
| SSH key pair | `{host_name}-key` | Saved to `~/.ssh/` |
| EBS data volume | `{host_name}-data` | Mounted at `/opt/apps`, survives termination |

---

## Quick Start

```bash
# 1. Install dependencies (from repo root)
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml --upgrade

# 2. Configure
cd deployment
cp group_vars/vault.yml.example group_vars/vault.yml
# Edit vault.yml with your settings, then encrypt:
ansible-vault encrypt group_vars/vault.yml --vault-password-file ~/.vault_pass

# 3. Load vars and provision
source scripts/load-vars.sh
ansible-playbook playbooks/provision-server.yml --vault-password-file ~/.vault_pass
```

Full guide: [deployment/docs/guides/QUICKSTART.md](deployment/docs/guides/QUICKSTART.md)

---

## Playbooks

### Provision
| Playbook | Purpose |
|---|---|
| `provision-server.yml` | Master — runs all steps below in order |
| `create-security-group.yml` | Security group — ports 22, 80, 443 |
| `create-iam-role.yml` | IAM role + instance profile |
| `create-ssh-key.yml` | SSH key pair → `~/.ssh/` |
| `launch-ec2-instance.yml` | EC2 instance + EBS data volume |
| `harden-server.yml` | OS hardening, supervisor, fail2ban, UFW |

### Maintain
| Playbook | Purpose |
|---|---|
| `update-server.yml` | Upgrade OS packages, re-apply config changes |

### Decommission
| Playbook | Purpose |
|---|---|
| `decommission.yml` | Master — removes all server AWS resources |
| `terminate-ec2-instance.yml` | Terminate the EC2 instance |
| `delete-ebs-volume.yml` | Delete the EBS data volume |
| `delete-ssh-key.yml` | Delete SSH key from AWS + local |
| `delete-security-group.yml` | Delete the security group |
| `delete-iam-role.yml` | Delete the IAM role + instance profile |
| `delete-iam-deployer-user.yml` | Delete the IAM deployer user (optional — pass `-e delete_deployer_user=true`) |

---

## Requirements

| Tool | Purpose | Min version |
|---|---|---|
| Python | Ansible runtime | 3.8+ |
| Ansible | Automation | 2.12+ |
| AWS CLI | AWS operations | 2.x |

```bash
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml --upgrade
```

---

## Project Structure

```
aws/
├── requirements.txt          Python dependencies (boto3, cryptography, etc.)
├── requirements.yml          Ansible collections (amazon.aws, community.general, ansible.posix)
└── deployment/
    ├── ansible.cfg           Ansible configuration
    ├── playbooks/            All playbooks (provision, update, decommission)
    ├── group_vars/
    │   ├── vault.yml         Your config — encrypted, gitignored
    │   └── vault.yml.example Template — copy and fill in
    ├── inventories/
    │   └── hosts.yml         Auto-generated with server IP on deploy
    ├── templates/            Jinja2 templates (fail2ban, logrotate, etc.)
    ├── scripts/
    │   ├── load-vars.sh      Source to load vault vars into shell
    │   ├── local-dev-setup.sh Setup/merge local config files
    │   └── decommission.sh   Interactive teardown wrapper
    └── docs/                 Full deployment guide (prerequisites → decommission)
```

---

## Multi-App

One server hosts multiple applications. After provisioning, each app deploys itself from its own repo using its own `setup.yml`. Each app needs a unique:

- `app_name` — drives all paths (`/opt/apps/{app_name}`), log dir, supervisor service
- `server_name` — FQDN (must resolve to this server's IP)
- `gunicorn_port` — unique loopback port per app (8000, 8001, 8002 …)

---

## Documentation

See [`deployment/docs/`](deployment/docs/README.md) for the full guide covering prerequisites, provisioning, operations, security hardening, and decommissioning.
