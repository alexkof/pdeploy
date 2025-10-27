# Python Deployment Scripts (pdeploy)

Universal bash scripts for deploying Python bot and web applications to Ubuntu servers.

## Features

- **One-command deployment** - Deploy Python apps with a single command
- **Automatic SSL** - Let's Encrypt SSL certificates for web apps via Traefik
- **Auto-restart** - Systemd service ensures your app restarts on failure
- **Web-based management** - Optional Cockpit UI for server and service monitoring
- **Clean deployment** - Standard `/opt/apps/{APP_NAME}` structure
- **Idempotent** - Safe to run multiple times
- **Minimal dependencies** - Only requires bash and SSH locally

## Requirements

### Local Machine
- Bash shell
- SSH client
- SSH key for server access

### Remote Server
- Ubuntu 24+ (clean install supported)
- SSH access with sudo/root privileges
- Domain pointed to server (for web apps with SSL)

## Quick Start

### 1. Create Your Application

Add a `pdeploy.config` file to your project root:

```ini
APP_NAME=myapp
APP_TYPE=bot
SERVER=111.22.33.44
SSH_USER=root
SSH_KEY=~/.ssh/id_rsa
MAIN_FILE=main.py
PYTHON_VERSION=3.11
```

For web applications, add:
```ini
APP_TYPE=web
WEB_PORT=8080
WEB_DOMAIN=myapp.example.com
WEB_LETSENCRYPT_EMAIL=admin@example.com
```

### 2. Initial Deployment

Copy the deployment scripts to your project:

```bash
cp pdeploy-init.sh your-project/
cp pdeploy.sh your-project/
cd your-project/
chmod +x pdeploy-init.sh pdeploy.sh
```

Run initial deployment:

```bash
./pdeploy-init.sh
```

This will:
- Connect to your server
- Install Python and system dependencies
- Create virtual environment
- Deploy your application
- Set up systemd service
- Install Docker and Traefik with SSL (for web apps)
- Start your application

### 3. Cockpit (Optional)

Install Cockpit for web-based server management:

```bash
./cockpit-init.sh
```

This will:
- Install Cockpit web UI
- Optionally create an admin user for Cockpit access
- Optionally disable SSH password authentication (key-only, recommended)

Access at `https://your-server-ip:9090` or use `./cockpit-tunnel.sh` for SSH tunneling.

### 4. Updates

For subsequent deployments:

```bash
./pdeploy.sh
```

This will:
- Stop the service
- Upload new code
- Update dependencies
- Restart the service
- Verify it's running

## Environment Configuration (.env Files)

The scripts use a safe convention for handling environment variables:

### How It Works

1. **If `.env.prod` exists locally** → Copied to server as `.env` (overwrites existing)
2. **Else if `.env` exists locally** → Copied to server as `.env` (overwrites existing)
3. **Else if `.env` exists on server** → Kept as-is (safe for manual edits)
4. **Else** → Script fails with error message

### Best Practices

**Local files (gitignored):**
- `.env` - For local development (also used for deployment if `.env.prod` doesn't exist)
- `.env.prod` - For production secrets (preferred for deployment)

**Committed to git:**
- `.env.example` - Template showing required variables

**Note:** You can use just `.env` for simple projects, or create `.env.prod` with production-specific values for more control.

### Example Setup

`.env.example` (committed to git):
```bash
API_KEY=your_api_key_here
DATABASE_URL=postgresql://...
DEBUG=false
```

`.env.prod` (gitignored, for deployment):
```bash
API_KEY=actual_production_key
DATABASE_URL=postgresql://prod-server/db
DEBUG=false
```

### Workflow

**First deployment:**
```bash
cp .env.example .env.prod
# Edit .env.prod with production values
./pdeploy-init.sh
```

**Update secrets on server:**
Option 1: Update `.env.prod` locally and redeploy
```bash
./pdeploy.sh  # Will copy new .env.prod
```

Option 2: Edit directly on server (will be preserved)
```bash
ssh user@server "nano /opt/apps/myapp/.env"
./pdeploy.sh  # Won't overwrite server .env
```

## Configuration Reference

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `APP_NAME` | Application name (used for service and directory) | `mybot` |
| `APP_TYPE` | Application type: `bot` or `web` | `bot` |
| `SERVER` | Server IP address or hostname | `111.22.33.44` |
| `SSH_USER` | SSH username | `root` |
| `SSH_KEY` | Path to SSH private key | `~/.ssh/id_rsa` |
| `MAIN_FILE` | Main Python file to execute | `main.py` |
| `PYTHON_VERSION` | Python version to install | `3.11` |

### Web Application Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `WEB_PORT` | Port your app listens on | `8080` |
| `WEB_DOMAIN` | Domain name for your app | `myapp.example.com` |
| `WEB_LETSENCRYPT_EMAIL` | Email for Let's Encrypt certificates | `admin@example.com` |

## Server Structure

After deployment, your app will be located at:

```
/opt/apps/{APP_NAME}/
├── venv/              # Virtual environment
├── main.py            # Your application files
├── requirements.txt
└── ...
```

Systemd service: `/etc/systemd/system/{APP_NAME}.service`

Traefik config (web apps): `/opt/traefik/`

## Managing Your Application

### Web UI (Cockpit)

If you installed Cockpit using `./cockpit-init.sh`, you can access the web-based management UI:

- **URL:** `https://your-server-ip:9090` or use `./cockpit-tunnel.sh`
- **Login:** Admin username and password (if you created one during Cockpit setup)

From Cockpit you can:
- Monitor server resources (CPU, memory, disk)
- View and control systemd services (start/stop/restart your app)
- View logs in real-time
- Monitor Docker containers (for web apps with Traefik)
- Manage server updates

If you haven't installed Cockpit yet, run `./cockpit-init.sh` to set it up.

### Command Line Management

#### Check Status

```bash
ssh user@server "systemctl status myapp"
```

#### View Logs

```bash
ssh user@server "journalctl -u myapp -f"
```

#### Manual Start/Stop

```bash
ssh user@server "systemctl stop myapp"
ssh user@server "systemctl start myapp"
ssh user@server "systemctl restart myapp"
```

## Test Applications

The `tests/` directory contains sample applications:

### Bot Application (`tests/bot-app/`)
- Simple Python bot that logs messages every 10 seconds
- Demonstrates basic bot deployment

### Web Application (`tests/web-app/`)
- Flask web app with API endpoints
- Demonstrates web deployment with SSL

To test:

```bash
cd tests/bot-app/
# Edit pdeploy.config with your server details
./pdeploy-init.sh
```

## Troubleshooting

### SSH Connection Failed
- Verify server IP and SSH key path
- Test manual connection: `ssh -i ~/.ssh/id_rsa user@server`
- Check firewall allows SSH (port 22)

### Service Failed to Start
- Check logs: `ssh user@server "journalctl -u myapp -n 50"`
- Verify `MAIN_FILE` exists and is executable
- Check Python dependencies installed correctly

### SSL Certificate Not Working
- Verify DNS points to your server IP
- Ensure ports 80 and 443 are open
- Check domain in `WEB_DOMAIN` is correct
- Certificates can take a few minutes to issue

### Web App Not Accessible
- Verify app listens on `0.0.0.0` not `127.0.0.1`
- Check `WEB_PORT` matches your application
- Ensure Traefik container is running: `ssh user@server "docker ps"`

### Cockpit Not Accessible
- Ensure port 9090 is open in firewall
- Check if Cockpit is running: `ssh user@server "systemctl status cockpit.socket"`
- Access using HTTPS: `https://server-ip:9090` (not HTTP)
- Accept the self-signed certificate warning in your browser

### Can't Login to Cockpit
- If you skipped user setup during Cockpit installation, create admin user: `ssh user@server 'adduser admin && usermod -aG sudo admin'`
- Root login is disabled by default in Cockpit for security
- Use the admin user you created, not root
- Or use the SSH tunnel method: `./cockpit-tunnel.sh`

## Security

### SSH Password Authentication

During `./cockpit-init.sh` setup, you can optionally:
1. Create a separate admin user with sudo access for Cockpit
2. Set a password for that user
3. Disable SSH password authentication (key-only)

**Benefits:**
- ✅ Prevents brute force attacks on SSH
- ✅ Forces SSH key authentication only
- ✅ Separate admin user for Cockpit (root stays passwordless)
- ✅ Admin user has sudo access for server management
- ✅ Deployment scripts continue to work normally with SSH keys

**Note:** Cockpit installation is completely optional and separate from app deployment

## Architecture

### Implementation Approach
- Uses SSH with heredoc to execute remote commands
- Main deployment scripts: `pdeploy-init.sh` (initial setup) and `pdeploy.sh` (updates)
- Optional Cockpit setup: `cockpit-init.sh` (separate, can run anytime)
- Helper scripts: `diagnose.sh`, `check-traefik.sh`, `cockpit-tunnel.sh`

### For Web Applications
- Traefik runs as Docker container
- Automatic HTTP to HTTPS redirect
- Let's Encrypt certificates auto-renewed
- Reverse proxy to your application

### For Bot Applications
- Simple systemd service
- Automatic restart on failure
- Logs via journald

### Server Management
- Cockpit provides web-based UI on port 9090
- Manage systemd services, view logs, monitor resources
- Access with SSH credentials

## File Exclusions

The following are automatically excluded from deployment:
- `venv/` - Virtual environment
- `__pycache__/` - Python cache
- `.git/` - Git repository
- `.env` - Local environment file (excluded, use `.env.prod` instead)
- `*.pyc`, `*.pyo` - Compiled Python
- `.pytest_cache/` - Test cache
- `.DS_Store` - macOS files

**Note:** `.env.prod` is **included** in deployment and renamed to `.env` on server

## License

MIT

## Support

For issues or questions, please refer to the `requirements` file for detailed specifications.
