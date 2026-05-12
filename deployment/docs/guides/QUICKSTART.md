# Quick Start

Provision the server in one command (~10–15 minutes).

> **Prerequisite:** Complete [Prerequisites](PREREQUISITES.md) first.

---

## 1. Load your variables

```bash
cd deployment
source scripts/load-vars.sh
```

Choose **option 1** if the server already exists (loads AWS instance IP into the shell), or **option 2** for a fresh deployment.

Variables available after sourcing (values come from your `group_vars/vault.yml`):

```
host_name={{ host_name }}
aws_region={{ aws_region }}
admin_user={{ admin_user }}
```

---

## 2. Provision the server

```bash
ansible-playbook playbooks/provision-server.yml --vault-password-file ~/.vault_pass
```

This is the only command needed. It runs all five steps in order:

| Step | Playbook | What it creates |
|------|----------|----------------|
| 1 | `create-security-group.yml` | Security group `{host_name}-sg` — ports 22, 80, 443 |
| 2 | `create-iam-role.yml` | IAM role `{host_name}-ec2-role` + instance profile |
| 3 | `create-ssh-key.yml` | Key pair `{host_name}-key` → `~/.ssh/{host_name}-key.pem` |
| 4 | `launch-ec2-instance.yml` | EC2 instance + EBS data volume at `apps_root` |
| 5 | `harden-server.yml` | OS hardening, nginx, supervisor, fail2ban, UFW |

**Duration:** 10–15 minutes (most of which is waiting for EC2 to become reachable)

**Idempotent:** Safe to re-run. Ansible skips steps that already exist.

> **Prefer doing it step by step, or want to understand each AWS CLI command?**
> See [Manual Deployment](MANUAL_DEPLOYMENT.md) — covers every step with AWS Console and CLI alternatives.

---

## 3. Find your server

Instance details are saved to `deployment/instances/`:

```bash
ls deployment/instances/
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

---

## 4. Connect via SSH

```bash
ssh -i {{ ssh_key_file }} ubuntu@<SERVER_IP>
```

Verify services are running:

```bash
sudo systemctl status nginx
sudo systemctl status supervisor
sudo ufw status
sudo fail2ban-client status
```

---

## 5. What is running on the server

After `harden-server.yml` completes the server has:

```
/opt/apps/           ← EBS data volume (100 GB, survives termination)
/var/log/apps/       ← shared log root

nginx                ← running, default-deny vhost active (returns 444 on IP-direct access)
supervisor           ← running, no programs yet (apps add their own)
fail2ban             ← running, SSH protection active
ufw                  ← active, default deny; 22/80/443 open
```

The server is **ready for application deployment** from each app's own repo.

Each app will:
- Add an nginx vhost under `/etc/nginx/sites-available/`
- Add a supervisor program under `/etc/supervisor/conf.d/`
- Deploy code to `/opt/apps/{app_name}/`
- Write logs to `/var/log/apps/{app_name}/`

---

## Run individual steps

If you need to re-run a single step:

```bash
ansible-playbook playbooks/create-security-group.yml --vault-password-file ~/.vault_pass
ansible-playbook playbooks/create-iam-role.yml        --vault-password-file ~/.vault_pass
ansible-playbook playbooks/create-ssh-key.yml         --vault-password-file ~/.vault_pass
ansible-playbook playbooks/launch-ec2-instance.yml    --vault-password-file ~/.vault_pass
ansible-playbook playbooks/harden-server.yml          --vault-password-file ~/.vault_pass
```

---

## Update the server

To apply OS package upgrades or re-apply configuration changes to a running server:

```bash
ansible-playbook playbooks/update-server.yml --vault-password-file ~/.vault_pass
```

This upgrades packages, re-applies nginx/fail2ban/SSH/sysctl config, and warns if a reboot is needed. Safe to run at any time without affecting app deployments.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Unable to locate credentials` | `aws configure` — re-enter deployer key and secret |
| `No module named 'boto3'` | `pip3 install -r requirements.txt` (run from repo root) |
| `UNREACHABLE` after EC2 launch | Wait 60–90 seconds for SSH to come up and re-run `harden-server.yml` |
| `Permission denied (publickey)` | Check `{{ ssh_key_file }}` exists and has `chmod 600` |
| Vault password wrong | `ansible-vault view group_vars/vault.yml --vault-password-file ~/.vault_pass` |
| SG already exists on re-run | Normal — Ansible is idempotent, it updates in place |
| EBS "device not found" | Instance type may not be Nitro-based; update `ebs_nvme_device` in vault |

---

## Next steps

- Deploy your first application from its own repo (`setup.yml` targeting this server's IP)
- [Decommission](DECOMMISSION.md) — when you need to tear everything down
- [Security Hardening](SECURITY_HARDENING.md) — verify and audit what was applied
