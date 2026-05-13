# Security Hardening

What `harden-server.yml` applies, how to verify each control, and how to audit the server.

---

## Overview

All hardening is applied automatically by `harden-server.yml` during `provision-server.yml`. Nothing requires manual configuration — this document explains what was applied so you can verify and audit it.

The hardening is **server-level**. Application-level controls (SSL certificates, log rotation per app) are the responsibility of each application's own deployment playbook.

---

## What Gets Applied

### SSH hardening

| Setting | Value | Config file |
|---------|-------|-------------|
| Password authentication | Disabled | `/etc/ssh/sshd_config` |
| Root login | Disabled | `/etc/ssh/sshd_config` |
| Max auth tries | 3 | `/etc/ssh/sshd_config` |
| X11 forwarding | Disabled | `/etc/ssh/sshd_config` |
| Client alive interval | 300 s | `/etc/ssh/sshd_config` |
| Client alive count max | 2 | `/etc/ssh/sshd_config` |

Verify:

```bash
ssh ubuntu@<SERVER_IP> -i {{ ssh_key_file }}
sudo grep -E "PasswordAuthentication|PermitRootLogin|MaxAuthTries|X11Forwarding|ClientAlive" /etc/ssh/sshd_config
```

---

### UFW firewall

Default policy: **deny inbound, allow outbound**

| Port | Protocol | Rule |
|------|----------|------|
| 22 | TCP | Allow |
| 80 | TCP | Allow |
| 443 | TCP | Allow |
| All other | — | Deny |

Verify:

```bash
sudo ufw status verbose
# Should show: Status active, Default: deny (incoming)
```

---

### Fail2ban — brute force protection

| Jail | Max retries | Find time | Ban time |
|------|-------------|-----------|----------|
| `sshd` | 5 | 20 min | 24 hours |

Verify:

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

Check current bans:

```bash
sudo fail2ban-client status sshd | grep "Banned IP"
```

Unban an IP:

```bash
sudo fail2ban-client set sshd unbanip <IP>
```

---

### Kernel protections (sysctl)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `net.ipv4.conf.all.rp_filter` | 1 | IP spoofing protection |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.tcp_max_syn_backlog` | 2048 | SYN flood protection |
| `net.ipv4.tcp_synack_retries` | 2 | SYN flood protection |
| `net.ipv4.conf.all.accept_source_route` | 0 | Disable source routing |
| `net.ipv4.conf.all.send_redirects` | 0 | Ignore ICMP redirects |
| `net.ipv4.conf.all.log_martians` | 1 | Log spoofed packets |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Ignore broadcast pings |
| `net.ipv6.conf.all.disable_ipv6` | 1 | IPv6 disabled |
| `net.ipv6.conf.default.disable_ipv6` | 1 | IPv6 disabled |

Verify:

```bash
sudo sysctl net.ipv4.tcp_syncookies
sudo sysctl net.ipv6.conf.all.disable_ipv6
sudo sysctl -a | grep rp_filter
```

---

### Shared memory

`/run/shm` is mounted with `noexec,nosuid` to prevent running code from shared memory — a common exploitation technique.

Verify:

```bash
mount | grep shm
# Should show: tmpfs on /run/shm ... (noexec,nosuid)
```

---

### Automatic security updates

| Setting | Value |
|---------|-------|
| Security patches | Auto-installed daily |
| Update check | Daily |
| Auto-reboot | Disabled (manual) |
| Unused kernel cleanup | Enabled |

Config files: `/etc/apt/apt.conf.d/20auto-upgrades`, `/etc/apt/apt.conf.d/50unattended-upgrades`

Verify:

```bash
sudo systemctl status unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
```

Check update log:

```bash
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades.log
```

---


### Supervisor

Supervisor is installed and running with no programs defined — it is the **shared process manager** for all applications. Each app's deployment playbook adds its own `conf.d/` entry.

Verify:

```bash
sudo supervisorctl status
# Should show: (no processes) or whatever apps have been deployed
sudo systemctl status supervisor
```

---

### Disabled services

These services are stopped and disabled if present: `apache2`, `avahi-daemon`, `cups`, `bluetooth`.

Verify:

```bash
for svc in apache2 avahi-daemon cups bluetooth; do
  sudo systemctl is-active $svc 2>/dev/null | xargs echo "$svc:"
done
# Expected: each shows "inactive" or "not-found"
```

---

### System logging

`rsyslog` and `logrotate` are configured for system-level logs. Application-level log rotation is managed by each app's own deployment.

```bash
sudo systemctl status rsyslog
ls /etc/logrotate.d/
```

---

## Full post-provision audit

Run this block on the server to verify all controls in one pass:

```bash
echo "=== SSH ==="
grep -E "^PasswordAuthentication|^PermitRootLogin|^MaxAuthTries|^X11Forwarding" /etc/ssh/sshd_config

echo ""
echo "=== UFW ==="
sudo ufw status verbose | head -20

echo ""
echo "=== Fail2ban ==="
sudo fail2ban-client status

echo ""
echo "=== Sysctl ==="
sudo sysctl net.ipv4.tcp_syncookies net.ipv6.conf.all.disable_ipv6 net.ipv4.tcp_syncookies

echo ""
echo "=== Services ==="
sudo systemctl is-active supervisor unattended-upgrades fail2ban

echo ""
echo "=== Shared memory ==="
mount | grep shm
```

---

## See also

- [Infrastructure](INFRASTRUCTURE.md) — the AWS resources
- [Architecture](../reference/ARCHITECTURE.md) — system design
- [Security Reference](../reference/SECURITY.md) — full control inventory with all values
