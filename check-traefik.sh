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
    echo "Run this script from your application directory"
    exit 1
fi

source "$CONFIG_FILE"

SSH_USER=${SSH_USER:-root}
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Traefik Configuration Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo "App: $APP_NAME"
echo "Domain: $WEB_DOMAIN"
echo "Port: $WEB_PORT"
echo ""

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << 'EOF'
echo "All Traefik dynamic configurations:"
echo "===================================="
echo ""

for config_file in /opt/traefik/dynamic/*.yml; do
    if [ -f "$config_file" ]; then
        echo -e "\033[1;33m$(basename $config_file):\033[0m"
        cat "$config_file"
        echo ""
        echo "------------------------------------"
        echo ""
    fi
done

echo ""
echo "Traefik container status:"
docker ps | grep traefik || echo "Traefik not running!"
echo ""

echo "Testing which app responds on each domain:"
echo "==========================================="
echo ""

# Extract all domains from configs
for config_file in /opt/traefik/dynamic/*.yml; do
    if [ -f "$config_file" ]; then
        DOMAIN=$(grep -oP 'Host\(\K[^)]+' "$config_file" | tr -d '\`"' | head -1)
        PORT=$(grep -oP 'http://localhost:\K\d+' "$config_file" | head -1)
        APP=$(basename "$config_file" .yml)

        if [ -n "$DOMAIN" ]; then
            echo "App: $APP"
            echo "  Domain: $DOMAIN"
            echo "  Backend port: $PORT"

            # Test localhost backend
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/ 2>/dev/null)
            echo "  Direct access (http://localhost:$PORT/): HTTP $STATUS"

            # Show a snippet of the response
            RESPONSE=$(curl -s http://localhost:$PORT/ 2>/dev/null | head -c 200)
            if [ -n "$RESPONSE" ]; then
                echo "  Response preview: ${RESPONSE:0:100}..."
            fi

            # Test via domain through Traefik
            DOMAIN_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $DOMAIN" http://localhost/ 2>/dev/null)
            echo "  Via Traefik (Host: $DOMAIN): HTTP $DOMAIN_STATUS"

            DOMAIN_RESPONSE=$(curl -s -H "Host: $DOMAIN" http://localhost/ 2>/dev/null | head -c 200)
            if [ -n "$DOMAIN_RESPONSE" ]; then
                echo "  Traefik response preview: ${DOMAIN_RESPONSE:0:100}..."
            fi

            echo ""
        fi
    fi
done

echo ""
echo "Traefik logs (last 30 lines):"
echo "=============================="
docker logs traefik --tail 30 2>&1

EOF

echo ""
echo -e "${YELLOW}Press any key to exit...${NC}"
read -n 1 -s -r
