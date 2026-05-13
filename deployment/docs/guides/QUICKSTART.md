# Quick Start

Choose the path that matches your situation:

- **[Deploy a new server](#deploy-a-new-server)** — first-time setup, nothing exists yet in AWS
- **[Work with an existing server](#work-with-an-existing-server)** — connect, update, or decommission a server that's already running

> **Prerequisite for both paths:** Complete [Prerequisites](PREREQUISITES.md) first.

---

## Deploy a New Server

### 1. Load your variables

```bash
cd deployment
source scripts/load-vars.sh
```

This reads `group_vars/vault.yml` and exports `host_name`, `aws_region`, and `admin_user` into your shell. If no server exists yet, no IP prompt appears.

### 2. Provision

```bash
ansible-playbook playbooks/provision-server.yml --vault-password-file ~/.vault_pass
```

This runs all five steps in order:

| Step | Playbook | What it creates |
|------|----------|----------------|
| 1 | `create-security-group.yml` | Security group `{host_name}-sg` — ports 22 (deployer IP only), 80, 443 |
| 2 | `create-iam-role.yml` | IAM role `{host_name}-ec2-role` + instance profile |
| 3 | `create-ssh-key.yml` | Key pair `{host_name}-key` → `~/.ssh/{host_name}-key.pem` |
| 4 | `launch-ec2-instance.yml` | EC2 instance + EBS data volume at `apps_root` |
| 5 | `harden-server.yml` | OS hardening, fail2ban, UFW, unattended-upgrades |

**Duration:** 10–15 minutes (most of which is waiting for EC2 to become reachable).

**Idempotent:** Safe to re-run — Ansible skips steps that already exist.

> **Prefer doing it step by step, or want to understand each AWS CLI command?**
> See [Manual Deployment](MANUAL_DEPLOYMENT.md).

### 3. Find your server

Instance details are saved to `deployment/instances/` automatically:

```bash
cat deployment/instances/*.txt
# Shows: server IP, instance ID, SSH command
```

Or query AWS directly:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$host_name" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
  --output table
```

### 4. Connect via SSH

```bash
ssh -i ~/.ssh/${host_name}-key.pem ubuntu@<SERVER_IP>
```

The exact SSH command is in `deployment/instances/*.txt`.

### 5. Verify the server

```bash
sudo systemctl is-active fail2ban unattended-upgrades
sudo ufw status
```

Expected: both services show `active`; UFW shows ports 22, 80, and 443 open with default deny.

The server foundation is now in place:

```
/opt/apps/           ← EBS data volume (100 GB, survives termination)
/var/log/apps/       ← shared log root

fail2ban             ← running, SSH brute-force protection active
ufw                  ← active, default deny; 22/80/443 open
unattended-upgrades  ← running, automatic security patches enabled
```

The server is **ready for application deployment** from each app's own repo.

Each app will:
- Add an nginx vhost under `/etc/nginx/sites-available/`
- Add a supervisor program under `/etc/supervisor/conf.d/`
- Deploy code to `/opt/apps/{app_name}/`
- Write logs to `/var/log/apps/{app_name}/`

### Run individual steps

If you need to re-run a single step:

```bash
ansible-playbook playbooks/create-security-group.yml --vault-password-file ~/.vault_pass
ansible-playbook playbooks/create-iam-role.yml        --vault-password-file ~/.vault_pass
ansible-playbook playbooks/create-ssh-key.yml         --vault-password-file ~/.vault_pass
ansible-playbook playbooks/launch-ec2-instance.yml    --vault-password-file ~/.vault_pass
ansible-playbook playbooks/harden-server.yml          --vault-password-file ~/.vault_pass
```

---

## Work with an Existing Server

### 1. Load your variables

```bash
cd deployment
source scripts/load-vars.sh
```

If `inventories/hosts.yml` contains a server IP, the script will prompt you to load it into `$server_ip`. Accept to use it in subsequent commands.

### 2. Connect via SSH

```bash
ssh -i ~/.ssh/${host_name}-key.pem ${admin_user}@${server_ip}
```

### 3. Update the server

Apply OS package upgrades and re-apply hardening config without touching app deployments:

```bash
ansible-playbook playbooks/update-server.yml --vault-password-file ~/.vault_pass
```

This also updates the security group SSH rule to your current public IP before connecting, so it works even if your IP has changed.

### 4. Decommission

To tear down all AWS resources for this server:

```bash
ansible-playbook playbooks/decommission.yml --vault-password-file ~/.vault_pass
```

See [Decommission](DECOMMISSION.md) for full details and what is and isn't deleted.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Unable to locate credentials` | `aws configure` — re-enter deployer key and secret |
| `No module named 'boto3'` | `pip install -r requirements.txt` (run from repo root) |
| `UNREACHABLE` after EC2 launch | Wait 60–90 seconds for SSH to come up and re-run `harden-server.yml` |
| `Permission denied (publickey)` | Check `~/.ssh/${host_name}-key.pem` exists and has `chmod 600` |
| Vault password wrong | `ansible-vault view group_vars/vault.yml --vault-password-file ~/.vault_pass` |
| SG already exists on re-run | Normal — Ansible is idempotent, it updates in place |
| EBS "device not found" | Instance type may not be Nitro-based; update `ebs_nvme_device` in vault |
| SSH blocked after IP change | Run `update-server.yml` from a location with current SG access, or update the SG manually in AWS Console |
