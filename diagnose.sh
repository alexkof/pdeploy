#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load configuration
CONFIG_FILE="pdeploy.config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    echo "Run this script from your application directory (not the pdeploy repo)"
    exit 1
fi

source "$CONFIG_FILE"

# Validate required parameters
if [ -z "$APP_NAME" ] || [ -z "$SERVER" ]; then
    echo -e "${RED}Error: APP_NAME and SERVER are required in $CONFIG_FILE${NC}"
    exit 1
fi

SSH_USER=${SSH_USER:-root}
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
SSH_KEY="${SSH_KEY/#\~/$HOME}"
WEB_PORT=${WEB_PORT:-8080}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnosing deployment issues${NC}"
echo -e "${BLUE}========================================${NC}"
echo "App: $APP_NAME"
echo "Server: $SERVER"
echo ""

# Test SSH connection
echo -e "${YELLOW}[1/5] Testing SSH connection...${NC}"
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ Cannot connect to server via SSH${NC}"
    exit 1
fi
echo ""

# Check service status
echo -e "${YELLOW}[2/5] Checking systemd service status...${NC}"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
APP_NAME="$APP_NAME"
if systemctl is-active --quiet \$APP_NAME.service; then
    echo -e "\033[0;32m✓ Service \$APP_NAME is RUNNING\033[0m"
else
    echo -e "\033[0;31m✗ Service \$APP_NAME is NOT RUNNING\033[0m"
    echo ""
    echo "Service status:"
    systemctl status \$APP_NAME.service --no-pager || true
fi
EOF
echo ""

# Check application logs
echo -e "${YELLOW}[3/5] Recent application logs (last 20 lines):${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "journalctl -u $APP_NAME.service -n 20 --no-pager"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""

# Check if app is listening on the port
echo -e "${YELLOW}[4/5] Checking if app is listening on port $WEB_PORT...${NC}"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
WEB_PORT="$WEB_PORT"
if netstat -tuln 2>/dev/null | grep -q ":$WEB_PORT " || ss -tuln 2>/dev/null | grep -q ":$WEB_PORT "; then
    echo -e "${GREEN}✓ Application is listening on port $WEB_PORT${NC}"
else
    echo -e "${RED}✗ Nothing is listening on port $WEB_PORT${NC}"
    echo ""
    echo "Common issues:"
    echo "  - App crashed or failed to start (check logs above)"
    echo "  - App listening on wrong port"
    echo "  - App listening on 127.0.0.1 instead of 0.0.0.0"
fi
EOF
echo ""

# Check Traefik status (for web apps)
if [ "$APP_TYPE" = "web" ]; then
    echo -e "${YELLOW}[5/5] Checking Traefik container...${NC}"
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
APP_NAME="$APP_NAME"
if docker ps | grep -q traefik; then
    echo -e "\033[0;32m✓ Traefik container is running\033[0m"
    echo ""
    echo "Traefik configuration for \$APP_NAME:"
    if [ -f "/opt/traefik/dynamic/\$APP_NAME.yml" ]; then
        cat /opt/traefik/dynamic/\$APP_NAME.yml
    else
        echo -e "\033[0;31m✗ Config file not found: /opt/traefik/dynamic/\$APP_NAME.yml\033[0m"
    fi
else
    echo -e "\033[0;31m✗ Traefik container is NOT running\033[0m"
    echo ""
    echo "Try restarting Traefik:"
    echo "  docker restart traefik"
fi
EOF
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnostic complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Quick fixes:${NC}"
echo ""
echo -e "1. If service is not running:"
echo -e "   ssh $SSH_USER@$SERVER \"systemctl restart $APP_NAME\""
echo ""
echo -e "2. If app is not listening on port:"
echo -e "   - Check your app listens on 0.0.0.0:$WEB_PORT (not 127.0.0.1)"
echo -e "   - Verify WEB_PORT=$WEB_PORT in pdeploy.config matches your app"
echo ""
echo -e "3. If Traefik is not running:"
echo -e "   ssh $SSH_USER@$SERVER \"docker restart traefik\""
echo ""
echo -e "4. View live logs:"
echo -e "   ssh $SSH_USER@$SERVER \"journalctl -u $APP_NAME -f\""
echo ""
echo -e "${YELLOW}Press any key to exit...${NC}"
read -n 1 -s -r
