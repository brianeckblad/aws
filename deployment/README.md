# Deployment

**Provision and harden a shared EC2 server for multiple applications.**

This repo handles **server infrastructure only**. App deployments (SSL, S3 buckets, Secrets Manager, nginx vhosts, supervisor programs) are managed from each app's own repo.

---

## What this provisions

```
EC2 (shared server)
├── nginx (shared reverse proxy — default-deny vhost; apps add their own)
├── supervisor (shared process manager — apps add their own programs)
├── fail2ban + UFW (OS hardening)
├── /opt/apps/         ← EBS data volume (survives instance termination)
└── /var/log/apps/     ← log root for all apps
```

| AWS Resource | Name | Notes |
|-------------|------|-------|
| EC2 instance | `{host_name}` | Ubuntu 24.04 LTS |
| Security group | `{host_name}-sg` | Ports 22, 80, 443 |
| IAM role | `{host_name}-ec2-role` | S3 wildcard, Secrets Manager, CloudWatch, SNS, SSM |
| SSH key pair | `{host_name}-key` | Saved to `~/.ssh/` |
| EBS data volume | `{host_name}-data` | Mounted at `/opt/apps`, survives termination |

---

## Usage

### Setup (once)

```bash
# From repo root
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml --upgrade

# Then switch into deployment/
cd deployment
cp group_vars/vault.yml.example group_vars/vault.yml
# Edit vault.yml, then encrypt:
ansible-vault encrypt group_vars/vault.yml --vault-password-file ~/.vault_pass
```

### Provision the server

```bash
ansible-playbook playbooks/provision-server.yml --vault-password-file ~/.vault_pass
```

### Decommission the server

```bash
ansible-playbook playbooks/decommission.yml --vault-password-file ~/.vault_pass \
  -e decommission_confirmed=true
```

---

## Playbooks

### Provision (run in order, or use provision-server.yml to run all)

| Playbook | Purpose |
|----------|---------|
| `provision-server.yml` | Master — runs all steps below in order |
| `create-security-group.yml` | Ports 22, 80, 443 |
| `create-iam-role.yml` | Server IAM role + instance profile |
| `create-ssh-key.yml` | SSH key pair |
| `launch-ec2-instance.yml` | EC2 + EBS data volume |
| `harden-server.yml` | OS hardening, nginx, supervisor, fail2ban, UFW |

### Update (running server)

| Playbook | Purpose |
|----------|---------|
| `update-server.yml` | Upgrade OS packages, re-apply config (nginx, fail2ban, SSH, sysctl) |

### Decommission (run in order, or use decommission.yml to run all)

| Playbook | Purpose |
|----------|---------|
| `decommission.yml` | Master — terminates EC2 and removes all server AWS resources |
| `terminate-ec2-instance.yml` | Terminate the EC2 instance |
| `delete-ssh-key.yml` | Delete SSH key from AWS + local |
| `delete-security-group.yml` | Delete the security group |
| `delete-iam-role.yml` | Delete the IAM role + instance profile |

---

## Multi-app

After the server is provisioned, each app deploys itself from its own repo by running its own `setup.yml` against this server's inventory. Apps need unique:
- `app_name` — drives paths (`/opt/apps/{app_name}`), log dir, supervisor service
- `server_name` — FQDN for nginx vhost + SSL cert (must resolve to this server's IP)
- `gunicorn_port` — unique loopback port (8000, 8001, 8002, …)

---

## Documentation

See [deployment/docs/](docs/README.md) for full deployment, operations, and teardown guides.
