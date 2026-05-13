# Security Reference

Complete inventory of all security controls applied by this repo, with configuration values and rationale.

---

## AWS-Level Controls

### Security Group (`{host_name}-sg`)

| Direction | Port | Protocol | Source | Rationale |
|-----------|------|----------|--------|-----------|
| Inbound | 22 | TCP | 0.0.0.0/0 | SSH — open to internet; host-level controls enforce auth |
| Inbound | 80 | TCP | 0.0.0.0/0 | HTTP |
| Inbound | 443 | TCP | 0.0.0.0/0 | HTTPS |
| Outbound | All | All | 0.0.0.0/0 | Package updates, Let's Encrypt, AWS APIs |

All other inbound traffic is **dropped** at the AWS perimeter.

### IAM Role (`{host_name}-ec2-role`)

| Policy | Action | Resource | Rationale |
|--------|--------|----------|-----------|
| `{host_name}-s3-access` | s3:GetObject, PutObject, DeleteObject, ListBucket | `arn:aws:s3:::*/*` | All apps on server; wildcard avoids IAM update per app |
| `{host_name}-secrets-access` | secretsmanager:GetSecretValue, DescribeSecret | `arn:aws:secretsmanager:{region}:*:secret:*` | All apps; wildcard avoids IAM update per app |
| `{host_name}-cloudwatch-access` | cloudwatch:Put*, logs:CreateLogGroup, logs:PutLogEvents | `*` | All apps may ship metrics/logs |
| `{host_name}-sns-access` | sns:Publish | `*` | All apps may send alerts |
| `{host_name}-serial-console-access` | ec2-instance-connect:SendSerialConsoleSSHPublicKey | `*` | Emergency console access if SSH is unreachable |
| `AmazonSSMManagedInstanceCore` | ssm:*, ec2messages:*, ssmmessages:* | `*` | AWS Systems Manager — session manager, run command, patch manager |

**No user credentials are stored on the server.** The role is assumed via EC2 instance metadata — temporary tokens only, rotated by AWS automatically.

---

## OS-Level Controls (`harden-server.yml`)

### SSH (`/etc/ssh/sshd_config`)

| Setting | Value | Rationale |
|---------|-------|-----------|
| `PasswordAuthentication` | `no` | Key-only auth; passwords are brute-forceable |
| `PermitRootLogin` | `no` | Root SSH access is never needed; use sudo |
| `MaxAuthTries` | `3` | Fail after 3 attempts; fail2ban bans the IP |
| `X11Forwarding` | `no` | Not needed; attack surface reduction |
| `ClientAliveInterval` | `300` | Detect dead connections after 5 minutes |
| `ClientAliveCountMax` | `2` | Disconnect after 10 minutes of inactivity |

### UFW Firewall

| Rule | Value |
|------|-------|
| Default inbound | `deny` |
| Default outbound | `allow` |
| Allow 22/tcp | SSH |
| Allow 80/tcp | HTTP |
| Allow 443/tcp | HTTPS |

UFW and the AWS Security Group both enforce these rules independently. This is defense-in-depth — a misconfigured SG does not expose the server.

### Fail2ban

| Jail | Max failures | Find window | Ban duration | Log source |
|------|-------------|-------------|--------------|-----------|
| `sshd` | 5 | 20 min | 24 hours | `/var/log/auth.log` |

The `recidive` jail is disabled — 7-day bans stored in iptables survive fail2ban restarts and can cause a week-long SSH lockout.

### Kernel Parameters (`/etc/sysctl.d/`)

| Parameter | Value | Protects against |
|-----------|-------|-----------------|
| `net.ipv4.conf.all.rp_filter` | 1 | IP spoofing |
| `net.ipv4.conf.default.rp_filter` | 1 | IP spoofing |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood |
| `net.ipv4.tcp_max_syn_backlog` | 2048 | SYN flood |
| `net.ipv4.tcp_synack_retries` | 2 | SYN flood |
| `net.ipv4.tcp_syn_retries` | 5 | SYN flood |
| `net.ipv4.conf.all.accept_source_route` | 0 | Source routing attacks |
| `net.ipv4.conf.default.accept_source_route` | 0 | Source routing attacks |
| `net.ipv4.conf.all.send_redirects` | 0 | ICMP redirect attacks |
| `net.ipv4.conf.default.send_redirects` | 0 | ICMP redirect attacks |
| `net.ipv4.conf.all.log_martians` | 1 | Log spoofed packets |
| `net.ipv4.conf.default.log_martians` | 1 | Log spoofed packets |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Smurf attacks |
| `net.ipv6.conf.all.disable_ipv6` | 1 | IPv6 attack surface (not used) |
| `net.ipv6.conf.default.disable_ipv6` | 1 | IPv6 attack surface (not used) |

### Shared Memory

`/run/shm` mounted `noexec,nosuid` — prevents execution of code placed in shared memory (a common privilege escalation vector).

### Automatic Security Updates (`unattended-upgrades`)

| Setting | Value |
|---------|-------|
| Origins | `Ubuntu:noble-security`, `Ubuntu:noble-updates` |
| Auto-install | Security patches only |
| Auto-reboot | Disabled (manual reboot required) |
| Unused kernel removal | Enabled |
| Package blacklist | None |

Update log: `/var/log/unattended-upgrades/unattended-upgrades.log`

### Disabled Services

Stopped and disabled on first run: `apache2`, `avahi-daemon`, `cups`, `bluetooth`

These services are not needed and represent unnecessary attack surface.

---


## Application-Level Scope

The following are **not** managed by this repo. Each app's own deployment handles:

| Control | Managed by |
|---------|-----------|
| SSL/TLS certificates | Each app's `setup.yml` (Let's Encrypt via certbot) |
| Reverse proxy config | Each app's `setup.yml` |
| App file permissions | Each app's `setup.yml` |
| App log rotation | Each app's `setup.yml` |
| Secrets Manager setup | Each app's `setup.yml` or admin |
| S3 bucket creation | Each app's `setup.yml` or admin |
| CloudFront CDN | Each app's `setup.yml` or admin |
| WAF | Each app's `setup.yml` or admin |

---

## See also

- [Security Hardening](../guides/SECURITY_HARDENING.md) — how to verify each control
- [Infrastructure](../guides/INFRASTRUCTURE.md) — IAM policy details
- [Architecture](ARCHITECTURE.md) — system design
