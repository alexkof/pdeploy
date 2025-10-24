# Test Bot Application

A simple Python bot for testing the pdeploy deployment scripts.

## What It Does

This bot runs continuously and logs a message every 10 seconds to demonstrate that it's running properly. It's perfect for testing bot deployments.

## Files

- `main.py` - Main bot script
- `requirements.txt` - Python dependencies
- `pdeploy.config` - Deployment configuration

## Setup

1. Edit `pdeploy.config` and update:
   - `SERVER` - Your server IP address
   - `SSH_USER` - SSH username (default: root)
   - `SSH_KEY` - Path to your SSH key

2. Copy the deployment scripts:
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

Updates:
```bash
./pdeploy.sh
```

## Monitor

Check if running:
```bash
ssh user@server "systemctl status testbot"
```

View logs:
```bash
ssh user@server "journalctl -u testbot -f"
```

You should see messages like:
```
Bot is alive! Counter: 1, Time: 2024-01-15 10:30:45.123456
Bot is alive! Counter: 2, Time: 2024-01-15 10:30:55.234567
```
