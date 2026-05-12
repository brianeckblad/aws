# Git Configuration

Set up your git identity for commits in this repository.

---

## Quick start

```bash
cd deployment
./scripts/configure-git.sh
```

The script reads `host_name` from `group_vars/vault.yml` and sets your git email to `{host_name}@brianeckblad.dev` for this repository.

Example output:

```
Git Configuration Setup
==================================================

📝 Configuration:
   Name: Brian Eckblad
   Email: web01@brianeckblad.dev
   Scope: Local (this repo)

✅ Local git config set (.git/config)
```

---

## Options

### Auto-detect (default)

Reads `host_name` from `group_vars/vault.yml`:

```bash
./scripts/configure-git.sh
```

### Specify name manually

```bash
./scripts/configure-git.sh web01
```

### Apply globally (all repos)

```bash
./scripts/configure-git.sh --global web01
```

---

## Verify

```bash
git config user.email
# → web01@brianeckblad.dev

git config --show-origin user.email
# → file:.git/config (local) or file:~/.gitconfig (global)
```

---

## Personalization

To change the name or email domain, edit the top of the script:

```bash
nano deployment/scripts/configure-git.sh
```

```bash
GIT_USER_NAME="Brian Eckblad"
EMAIL_DOMAIN="brianeckblad.dev"
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Not in a git repository" | Run from the repo root, or use `--global` |
| "Could not determine server name" | Specify it: `./scripts/configure-git.sh web01` |
| vault.yml encrypted, no `~/.vault_pass` | Script falls back to asking for the password |
