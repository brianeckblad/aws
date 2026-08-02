# Redeploy

Rebuild the EC2 instance with a fresh, fully-patched OS **while preserving your data**. The EBS data volume mounted at `apps_root` survives instance termination (`ebs_data_delete_on_termination: false`), so `/opt/apps` is retained across a redeploy.

Counterpart playbook: [`playbooks/redeploy-server.yml`](../../playbooks/redeploy-server.yml)

---

## When to Redeploy

- An OS/kernel update left the instance in a broken state
- You want the latest Ubuntu 24.04 LTS image (faster than a long `apt upgrade`)
- The instance has persistent issues and you want a clean base
- You are changing instance type and want minimal fuss

---

## What It Does

`redeploy-server.yml` runs these steps in order:

```
redeploy-server.yml            (master)
  1. terminate-ec2-instance.yml   (data volume survives)
  2. launch-ec2-instance.yml      (latest Ubuntu 24.04 LTS AMI)
  3. reattach existing data volume
  4. harden-server.yml            (SSH, UFW, fail2ban, sysctl, supervisor)
```

The reattach step auto-detects your existing data volume (tagged `{host_name}-data`), detaches the freshly-created empty volume, attaches your original one, and updates `inventories/hosts.yml` and `~/.ssh/config` with the new public IP.

---

## Prerequisites

Load your deployment variables (this also exports `AWS_PROFILE` if `aws_profile` is set in your vault):

```bash
cd deployment
source scripts/load-vars.sh
```

---

## Single-Command Redeploy

```bash
uv run ansible-playbook playbooks/redeploy-server.yml --vault-password-file ~/.vault_pass
```

The playbook prints a plan (current instance, data volume, new-IP warning) and pauses for confirmation before making any changes.

---

## Step-by-Step Redeploy

Every step is also an independent playbook, consistent with the rest of this project.

### 1. Terminate the current instance

```bash
uv run ansible-playbook playbooks/terminate-ec2-instance.yml --vault-password-file ~/.vault_pass
```

Disables termination protection and terminates the instance. The data volume remains (it is not deleted on termination).

### 2. Launch a new instance

```bash
uv run ansible-playbook playbooks/launch-ec2-instance.yml --vault-password-file ~/.vault_pass
```

Selects the latest Ubuntu 24.04 LTS AMI and launches a new instance. This creates a **new empty** data volume — the next step swaps in your original.

### 3. Reattach the existing data volume

The reattach play lives inside `redeploy-server.yml`. After a manual launch you can run just that logic; it detects the available data volume and swaps it in:

```bash
uv run ansible-playbook playbooks/redeploy-server.yml \
  --vault-password-file ~/.vault_pass \
  --start-at-task="Get newly launched instance"
```

### 4. Harden the new instance

```bash
uv run ansible-playbook playbooks/harden-server.yml --vault-password-file ~/.vault_pass
```

Applies OS hardening, firewall, fail2ban, and mounts the data volume at `apps_root`.

---

## Post-Redeploy Checklist

A new public IP is assigned on redeploy. After it completes:

1. **Update DNS** — point your app domains at the new IP (shown in the summary and in `instances/{id}.txt`).
2. **Test SSH** — `ssh {host_name}` (the `~/.ssh/config` entry is updated automatically).
3. **Verify the server** — confirm all AWS resources and server health in one pass:
   ```bash
   uv run ansible-playbook playbooks/verify.yml --vault-password-file ~/.vault_pass
   ```
4. **Verify data** — `ls -la /opt/apps` should show your apps.
5. **Restart apps** — services do not auto-start after a redeploy:
   ```bash
   ssh {host_name}
   sudo supervisorctl restart all
   ```
   Or redeploy each app from its own repo.

---

## Troubleshooting

### No data volume found

The old data volume may be missing its tags. Confirm it exists and tag it:

```bash
aws ec2 describe-volumes --region "$aws_region" \
  --filters "Name=tag:Server,Values=$host_name" \
  --query 'Volumes[*].[VolumeId,State,Size]' --output table

aws ec2 create-tags --resources vol-xxxxxxxx \
  --tags Key=Name,Value="${host_name}-data" Key=Server,Value="$host_name"
```

### Apps not starting after redeploy

The instance is new; restart services:

```bash
ssh {host_name}
sudo supervisorctl restart all
```

### Permission denied (publickey)

The inventory/SSH config updates on redeploy. If you connected before it finished, retry with the explicit key:

```bash
ssh -i ~/.ssh/{host_name}-key.pem ubuntu@<NEW_IP>
```

---

## Notes on Credentials

If your AWS credentials live under a named profile, set `aws_profile` in `group_vars/vault.yml`. `source scripts/load-vars.sh` then exports `AWS_PROFILE` for both the AWS CLI and the `amazon.aws` modules. See [AWS Deployer User](AWS_DEPLOYER_USER.md).

