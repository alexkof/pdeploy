# Test Web Application

A simple Flask web application for testing the pdeploy deployment scripts with SSL/HTTPS support.

## What It Does

This web app provides:
- A simple HTML homepage
- `/api/status` - JSON API endpoint showing app status
- `/api/health` - Health check endpoint

Perfect for testing web application deployments with Traefik and Let's Encrypt SSL.

## Files

- `app.py` - Flask application
- `requirements.txt` - Python dependencies (Flask, Werkzeug)
- `pdeploy.config` - Deployment configuration

## Setup

1. **Point your domain to your server**
   - Create an A record for your domain (e.g., `test.example.com`) pointing to your server IP
   - This is required for SSL certificates to work

2. **Edit `pdeploy.config`** and update:
   - `SERVER` - Your server IP address
   - `SSH_USER` - SSH username (default: root)
   - `SSH_KEY` - Path to your SSH key
   - `WEB_DOMAIN` - Your domain name (e.g., `test.example.com`)
   - `WEB_LETSENCRYPT_EMAIL` - Your email for Let's Encrypt

3. **Copy the deployment scripts:**
   ```bash
   cp ../../pdeploy-init.sh .
   cp ../../pdeploy.sh .
   chmod +x pdeploy-init.sh pdeploy.sh
   ```

## Deploy

First time:
```bash
./pdeploy-init.sh
```

This will:
- Set up the server
- Install Docker and Traefik
- Deploy your app
- Configure SSL with Let's Encrypt

Updates:
```bash
./pdeploy.sh
```

## Access Your App

After deployment:
- **HTTPS**: `https://test.example.com` (or your domain)
- **API Status**: `https://test.example.com/api/status`
- **Health Check**: `https://test.example.com/api/health`

HTTP requests are automatically redirected to HTTPS.

## Monitor

Check if running:
```bash
ssh user@server "systemctl status testweb"
```

View app logs:
```bash
ssh user@server "journalctl -u testweb -f"
```

Check Traefik:
```bash
ssh user@server "docker ps | grep traefik"
```

## Troubleshooting

### SSL Certificate Not Working

Wait a few minutes after deployment - Let's Encrypt needs time to issue certificates.

Verify:
- DNS is pointing to your server
- Ports 80 and 443 are open
- Domain matches `WEB_DOMAIN` in config

### App Not Accessible

Check Traefik logs:
```bash
ssh user@server "docker logs traefik"
```

Verify app is listening:
```bash
ssh user@server "netstat -tlnp | grep 8080"
```
