# Quick Start Guide

## 0. Prerequisites (Windows Users)

**For Windows users using Git Bash:**

The scripts work without rsync, but installing it makes deployments much faster (only uploads changed files).

**Optional - Install rsync for faster deployments:**
- Use WSL (Windows Subsystem for Linux) - recommended
- Or install via Chocolatey: `choco install rsync`
- Or use MSYS2: `pacman -S rsync`

**Without rsync:** Scripts will work but copy all files every time (slower).

## 1. Setup SSH Key

Generate an SSH key if you don't have one:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/deploy_key
```

**Supported formats:**
- **RSA** (recommended): `ssh-keygen -t rsa -b 4096`
- **Ed25519**: `ssh-keygen -t ed25519`
- **ECDSA**: `ssh-keygen -t ecdsa -b 521`

Example RSA private key format (`~/.ssh/id_rsa`):
```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
...
-----END RSA PRIVATE KEY-----
```

Copy **public key** to server:
```bash
ssh-copy-id -i ~/.ssh/deploy_key.pub root@your-server-ip
```

## 2. Configure Your Project

Create `pdeploy.config`:

```ini
APP_NAME=myapp
APP_TYPE=bot
SERVER=111.22.33.44
SSH_USER=root
SSH_KEY=~/.ssh/deploy_key       # Path to PRIVATE key (not .pub)
MAIN_FILE=main.py
PYTHON_VERSION=3.11
```

For web apps, add:
```ini
APP_TYPE=web
WEB_PORT=8080
WEB_DOMAIN=myapp.example.com
WEB_LETSENCRYPT_EMAIL=admin@example.com
```

## 3. Create Environment File

```bash
cp .env.example .env.prod
nano .env.prod  # Add your secrets
```

## 4. Deploy

**First time:**
```bash
chmod +x pdeploy-init.sh pdeploy.sh
./pdeploy-init.sh
```

During setup, you'll be asked:
- **Cockpit admin user setup**: Recommended to say "yes"
  - Creates a new admin user (default: "admin") with sudo access
  - Sets password for Cockpit web UI login
  - Disables SSH password authentication (key-only, more secure)
  - Your deployment scripts continue to work with SSH keys

**Updates:**
```bash
./pdeploy.sh
```

## 5. Access

**Your app:**
- Bot: Check logs with `ssh user@server "journalctl -u myapp -f"`
- Web: Visit `https://your-domain.com`

**Server UI:**
- Cockpit: `https://your-server-ip:9090`

Done!
