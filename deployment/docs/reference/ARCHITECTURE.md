# Architecture

System design, deployment model, and technology choices.

---

## Deployment Model

This repo implements **Layer 1** of a two-layer deployment model. Each layer is independent and managed separately.

```
Layer 1 — Server Foundation (this repo)
┌────────────────────────────────────────────────────────┐
│                                                        │
│  provision-server.yml                                  │
│  ├── Security group     {host_name}-sg                 │
│  ├── IAM role           {host_name}-ec2-role           │
│  ├── SSH key pair       {host_name}-key                │
│  ├── EC2 instance       Ubuntu 24.04, t3.small          │
│  │   └── EBS data vol   /opt/apps (100 GB, XFS)        │
│  └── harden-server.yml                                 │
│      ├── SSH: key-only, no root, fail2ban, idle timeout│
│      ├── UFW: default deny; allow 22, 80, 443          │
│      ├── sysctl: SYN flood, IP spoof, IPv6 disabled    │
│      ├── unattended-upgrades: daily security patches   │
│      └── supervisor: shared process manager (empty)    │
└────────────────────────────────────────────────────────┘

Layer 2 — Application Deployment (each app's own repo)
┌────────────────────────────────────────────────────────┐
│                                                        │
│  setup.yml (per app)                                   │
│  ├── reverse proxy + SSL  (managed by app's setup.yml)    │
│  ├── supervisor program /etc/supervisor/conf.d/        │
│  ├── Python venv        /opt/apps/{app_name}/.venv     │
│  ├── app code           /opt/apps/{app_name}/          │
│  └── app logs           /var/log/apps/{app_name}/      │
└────────────────────────────────────────────────────────┘
```

Layer 1 runs **once** per server. Layer 2 runs once per application, then uses `update.yml` for code upgrades.

---

## Multi-App Isolation

Multiple applications share one EC2 instance with the following isolation:

| Resource | How isolation works |
|----------|-------------------|
| File system | Each app gets `/opt/apps/{app_name}/` with its own Unix user and permissions |
| Network | Each app listens on a unique loopback port (`127.0.0.1:8000`, `8001`, …); reverse proxy routes by `server_name` |
| Processes | Each app is a separate supervisor program with its own restart policy |
| Logs | Each app writes to `/var/log/apps/{app_name}/` |
| Secrets | Each app reads its own Secrets Manager path (`{app_name}/production`) |
| S3 | Each app uses its own bucket; the shared IAM role covers all by wildcard |

---

## Infrastructure Components

### EC2 Instance

- **OS:** Ubuntu 24.04 LTS
- **Default type:** t3.small (Nitro-based, NVMe EBS)
- **AMI:** Latest Ubuntu 24.04 LTS resolved at deploy time via `amazon.aws.ec2_ami_info`
- **EBS root:** gp3, 8 GB, deleted on termination (OS + config only)
- **EBS data:** gp3, 100 GB, encrypted, **survives termination** — all app code and data live here

### IAM Role

- **Type:** EC2 instance role — no credentials stored on disk
- **Scope:** Covers all apps on the server with wildcard S3 and Secrets Manager policies
- **Managed policy:** `AmazonSSMManagedInstanceCore` — Systems Manager access

### Security Group

- **Ingress:** 22 (SSH), 80 (HTTP), 443 (HTTPS) from `0.0.0.0/0`
- **Egress:** All traffic (package updates, Let's Encrypt, AWS APIs)
- **Complemented by:** UFW on the host (defense-in-depth)

---

## Playbook Design

Each playbook does exactly one thing and reports exactly what changed:

```
create-security-group.yml   → idempotent: updates rules if SG exists
create-iam-role.yml         → idempotent: creates or updates policies
create-ssh-key.yml          → create-only: skips if key already exists in AWS
launch-ec2-instance.yml     → create-only: skips if instance with Name tag exists
harden-server.yml           → idempotent: applies config, skips already-correct
```

**Idempotency:** All playbooks are safe to re-run. Use this when troubleshooting — re-run only the failing playbook without touching resources from earlier steps.

---

## Local Toolchain

```
Local Machine
├── Ansible playbooks   (this repo's /deployment/playbooks/)
├── group_vars/
│   ├── vault.yml       (encrypted — single source of truth)
│   └── all.yml         (stub)
├── inventories/
│   └── hosts.yml       (updated automatically on launch-ec2-instance.yml)
└── scripts/
    ├── local-dev-setup.sh    → scaffold vault.yml from template
    ├── load-vars.sh          → source: exports vault vars to shell
    ├── decommission.sh       → interactive wrapper around decommission.yml
    ├── configure-git.sh      → set git identity from host_name
    ├── vault-password.sh     → vault password helper
    └── merge_yaml.py         → YAML merge utility for local-dev-setup.sh
```

---

## Technology Choices

| Technology | Why |
|-----------|-----|
| **Ubuntu 24.04 LTS** | Long-term support until 2029; standard for Python apps; AWS provides maintained AMIs |
| **supervisor** | Simple process manager for Python apps; auto-restart on crash; centralized log management |
| **fail2ban** | Automatic IP banning on repeated SSH failures; works with UFW |
| **UFW** | Simple iptables frontend; clear allow/deny rules; complements AWS Security Group |
| **XFS on EBS** | Performant for many small files (Python bytecode, logs); supports online resize |
| **Ansible vault** | Encrypted secrets committed to git — no separate secrets backend required for deployment config |
| **gp3 EBS** | Configurable IOPS independent of size; lower cost than gp2 at the same performance |

---

## See also

- [Infrastructure](../guides/INFRASTRUCTURE.md) — detailed resource configuration
- [Security](SECURITY.md) — complete control inventory
- [Security Hardening](../guides/SECURITY_HARDENING.md) — verification guide
