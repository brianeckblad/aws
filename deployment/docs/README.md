# Deployment Documentation

**Scope:** Provision and harden a shared EC2 server. This repo handles server infrastructure only.

---

## Guides

| Guide | What it covers |
|-------|---------------|
| [Prerequisites](guides/PREREQUISITES.md) | AWS account, local tools, vault setup |
| [Quick Start](guides/QUICKSTART.md) | Provision the server in one command |
| [Manual Deployment](guides/MANUAL_DEPLOYMENT.md) | Step-by-step with AWS Console and CLI for each resource |
| [Decommission](guides/DECOMMISSION.md) | Tear down the server and remove all AWS resources |
| [Git Configuration](guides/GIT_CONFIGURATION.md) | Configure git identity for this repo |
| [Infrastructure](guides/INFRASTRUCTURE.md) | AWS resource reference (EC2, IAM, SG, SSH key, EBS) |
| [Security Hardening](guides/SECURITY_HARDENING.md) | What `harden-server.yml` applies and how to verify it |

## Reference

| Reference | What it covers |
|-----------|---------------|
| [Architecture](reference/ARCHITECTURE.md) | System design and deployment model |
| [Security](reference/SECURITY.md) | Security controls, configuration values, and audit guide |

---

## Two-Layer Deployment Model

```
Layer 1 — Server Foundation (this repo)
  EC2 instance + OS hardening + supervisor + fail2ban + UFW
  All resources named after host_name

Layer 2 — Application Deployment (each app's own repo)
  Reverse proxy, SSL cert, supervisor program, Python venv, app code
  Resources named after app_name; paths under /opt/apps/{app_name}
```

Run **Layer 1 once** per server. Run **Layer 2** for each application you host.

---

## Playbook Summary

```
Provision:
  provision-server.yml          ← master (runs all 5 below in order)
  ├── create-security-group.yml
  ├── create-iam-role.yml
  ├── create-ssh-key.yml
  ├── launch-ec2-instance.yml
  └── harden-server.yml

Decommission:
  decommission.yml              ← master (runs all 6 below in order)
  ├── terminate-ec2-instance.yml
  ├── delete-ebs-volume.yml
  ├── delete-ssh-key.yml
  ├── delete-security-group.yml
  ├── delete-iam-role.yml
  └── delete-iam-deployer-user.yml  ← skipped unless -e delete_deployer_user=true
```
