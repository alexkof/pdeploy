#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration
CONFIG_FILE="pdeploy.config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    exit 1
fi

# Source config file
source "$CONFIG_FILE"

# Validate required parameters
if [ -z "$APP_NAME" ]; then
    echo -e "${RED}Error: APP_NAME is required in $CONFIG_FILE${NC}"
    exit 1
fi

if [ -z "$APP_TYPE" ] || { [ "$APP_TYPE" != "bot" ] && [ "$APP_TYPE" != "web" ]; }; then
    echo -e "${RED}Error: APP_TYPE must be 'bot' or 'web'${NC}"
    exit 1
fi

if [ -z "$SERVER" ]; then
    echo -e "${RED}Error: SERVER is required${NC}"
    exit 1
fi

# Set defaults
SSH_USER=${SSH_USER:-root}
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
MAIN_FILE=${MAIN_FILE:-main.py}
PYTHON_VERSION=${PYTHON_VERSION:-3.11}
WEB_PORT=${WEB_PORT:-8080}

# Validate web-specific parameters
if [ "$APP_TYPE" = "web" ]; then
    if [ -z "$WEB_DOMAIN" ]; then
        echo -e "${RED}Error: WEB_DOMAIN is required for web applications${NC}"
        exit 1
    fi
    if [ -z "$WEB_LETSENCRYPT_EMAIL" ]; then
        echo -e "${RED}Error: WEB_LETSENCRYPT_EMAIL is required for web applications${NC}"
        exit 1
    fi
fi

# Expand SSH key path
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo -e "${GREEN}Starting deployment initialization for $APP_NAME${NC}"
echo "Server: $SERVER"
echo "User: $SSH_USER"
echo "Type: $APP_TYPE"
echo "Python: $PYTHON_VERSION"

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to server via SSH${NC}"
    exit 1
fi
echo -e "${GREEN}SSH connection successful${NC}"

# Execute server setup via SSH with heredoc
echo ""
echo -e "${YELLOW}Setting up server...${NC}"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
set -e

APP_NAME="$APP_NAME"
APP_TYPE="$APP_TYPE"
PYTHON_VERSION="$PYTHON_VERSION"
MAIN_FILE="$MAIN_FILE"
WEB_PORT="$WEB_PORT"
WEB_DOMAIN="$WEB_DOMAIN"
WEB_LETSENCRYPT_EMAIL="$WEB_LETSENCRYPT_EMAIL"
APP_DIR="/opt/apps/\$APP_NAME"

echo "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq software-properties-common build-essential libssl-dev libffi-dev \
    python3-dev python3-pip python3-venv curl wget git > /dev/null

# Check if Python version is available
echo "Checking Python version..."
PYTHON_CMD="python\${PYTHON_VERSION}"

if ! command -v \$PYTHON_CMD &> /dev/null; then
    echo "Installing Python \$PYTHON_VERSION..."
    add-apt-repository ppa:deadsnakes/ppa -y > /dev/null 2>&1
    apt-get update -qq
    apt-get install -y -qq python\${PYTHON_VERSION} python\${PYTHON_VERSION}-venv python\${PYTHON_VERSION}-dev > /dev/null
fi

# Verify Python version
INSTALLED_VERSION=\$(\$PYTHON_CMD --version 2>&1 | grep -oP '\d+\.\d+')
if [ "\$INSTALLED_VERSION" != "\$PYTHON_VERSION" ]; then
    echo "Error: Python version mismatch. Expected \$PYTHON_VERSION, got \$INSTALLED_VERSION"
    exit 1
fi

echo "Python \$PYTHON_VERSION is ready"

# Create application directory
echo "Creating application directory at \$APP_DIR..."
mkdir -p "\$APP_DIR"

# Create virtual environment
echo "Creating virtual environment..."
\$PYTHON_CMD -m venv "\$APP_DIR/venv"

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/\$APP_NAME.service << SERVICE
[Unit]
Description=\$APP_NAME Python Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=\$APP_DIR
Environment="PATH=\$APP_DIR/venv/bin"
ExecStart=\$APP_DIR/venv/bin/python \$APP_DIR/\$MAIN_FILE
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable \$APP_NAME.service > /dev/null 2>&1

# Setup Docker and Traefik for web applications
if [ "\$APP_TYPE" = "web" ]; then
    echo "Setting up Traefik for web application..."

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh > /dev/null 2>&1
        rm get-docker.sh
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker
    fi

    # Create Traefik directories
    mkdir -p /opt/traefik
    mkdir -p /opt/traefik/letsencrypt

    # Create Traefik configuration
    cat > /opt/traefik/traefik.yml << TRAEFIK
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: \$WEB_LETSENCRYPT_EMAIL
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true

api:
  dashboard: false
TRAEFIK

    # Create dynamic configuration directory
    mkdir -p /opt/traefik/dynamic

    # Create dynamic configuration for this app
    cat > /opt/traefik/dynamic/\$APP_NAME.yml << DYNAMIC
http:
  routers:
    \$APP_NAME:
      rule: "Host(\\\`\$WEB_DOMAIN\\\`)"
      service: \$APP_NAME
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    \$APP_NAME:
      loadBalancer:
        servers:
          - url: "http://localhost:\$WEB_PORT"
DYNAMIC

    # Start Traefik container if not running
    if ! docker ps | grep -q traefik; then
        echo "Starting Traefik container..."
        docker run -d \
            --name traefik \
            --restart always \
            --network host \
            -v /opt/traefik/traefik.yml:/etc/traefik/traefik.yml:ro \
            -v /opt/traefik/dynamic:/etc/traefik/dynamic:ro \
            -v /opt/traefik/letsencrypt:/letsencrypt \
            traefik:v2.10 > /dev/null
    else
        echo "Traefik already running, restarting to apply configuration..."
        docker restart traefik > /dev/null
    fi
fi

echo "Server setup complete!"
EOF

echo -e "${GREEN}Server setup completed successfully${NC}"

# Handle .env file configuration
echo -e "${YELLOW}Checking environment configuration...${NC}"

ENV_FILE_TO_COPY=""
if [ -f ".env.prod" ]; then
    echo "Found .env.prod, will use it as .env on server"
    ENV_ACTION="copy"
    ENV_FILE_TO_COPY=".env.prod"
elif [ -f ".env" ]; then
    echo "Found .env (no .env.prod), will use it as .env on server"
    ENV_ACTION="copy"
    ENV_FILE_TO_COPY=".env"
elif ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "[ -f /opt/apps/$APP_NAME/.env ]" 2>/dev/null; then
    echo "No local .env file found, but .env exists on server - will keep existing"
    ENV_ACTION="keep"
else
    echo -e "${RED}Error: No .env or .env.prod file found locally and no .env exists on server${NC}"
    echo -e "${RED}Please create .env.prod (or .env) with your configuration${NC}"
    exit 1
fi

# Copy application files to server
echo -e "${YELLOW}Uploading application files...${NC}"

# Start timing
UPLOAD_START=$(date +%s)

# Check if rsync is available and working (not broken Git Bash version)
USE_RSYNC=false
if command -v rsync &> /dev/null; then
    # Check if we're in Git Bash on Windows (rsync doesn't work properly there)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$MSYSTEM" ]] || uname -s | grep -qi "mingw\|msys"; then
        echo -e "${YELLOW}Git Bash detected - rsync not fully compatible, using fallback method${NC}"
    else
        USE_RSYNC=true
    fi
fi

if [ "$USE_RSYNC" = true ]; then
    # Use rsync for efficient transfer (only changed files)
    echo "Using rsync (efficient - only changed files will be uploaded)"
    rsync -avz --exclude='venv' --exclude='__pycache__' --exclude='.git' \
        --exclude='.env' --exclude='*.pyc' --exclude='.pytest_cache' \
        --exclude='*.pyo' --exclude='.gitignore' --exclude='.DS_Store' \
        -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        ./ "$SSH_USER@$SERVER:/opt/apps/$APP_NAME/" > /dev/null
else
    # Fallback to cp + scp (works without rsync or with incompatible rsync)
    if ! command -v rsync &> /dev/null; then
        echo "rsync not available - copying all files (for faster deploys, use WSL or install rsync)"
    fi

    # Create temporary directory for files to upload
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # Copy files excluding unwanted directories
    find . -type f \
        ! -path './venv/*' ! -path './__pycache__/*' ! -path './.git/*' \
        ! -path './.pytest_cache/*' ! -name '*.pyc' ! -name '*.pyo' \
        ! -name '.gitignore' ! -name '.DS_Store' ! -name '.env' \
        -exec cp --parents {} "$TEMP_DIR/" \; 2>/dev/null || \
    find . -type f \
        ! -path './venv/*' ! -path './__pycache__/*' ! -path './.git/*' \
        ! -path './.pytest_cache/*' ! -name '*.pyc' ! -name '*.pyo' \
        ! -name '.gitignore' ! -name '.DS_Store' ! -name '.env' \
        | while read file; do
            mkdir -p "$TEMP_DIR/$(dirname "$file")"
            cp "$file" "$TEMP_DIR/$file"
        done

    # Upload to server
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$TEMP_DIR"/* "$SSH_USER@$SERVER:/opt/apps/$APP_NAME/" > /dev/null 2>&1
fi

# Handle .env file if present
if [ "$ENV_ACTION" = "copy" ] && [ -n "$ENV_FILE_TO_COPY" ]; then
    echo -e "${YELLOW}Copying $ENV_FILE_TO_COPY to server as .env...${NC}"
    # Copy the env file to server
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$ENV_FILE_TO_COPY" "$SSH_USER@$SERVER:/opt/apps/$APP_NAME/.env.tmp" > /dev/null 2>&1
    # Rename to .env on server
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "mv /opt/apps/$APP_NAME/.env.tmp /opt/apps/$APP_NAME/.env" 2>/dev/null || true
fi

# Calculate upload time
UPLOAD_END=$(date +%s)
UPLOAD_TIME=$((UPLOAD_END - UPLOAD_START))

echo -e "${GREEN}Files uploaded successfully in ${UPLOAD_TIME}s${NC}"

# Install dependencies and start service
echo -e "${YELLOW}Installing dependencies and starting service...${NC}"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
set -e
APP_NAME="$APP_NAME"
APP_TYPE="$APP_TYPE"
WEB_PORT="$WEB_PORT"
APP_DIR="/opt/apps/\$APP_NAME"

cd "\$APP_DIR"

# Install dependencies if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "Installing Python dependencies..."
    "\$APP_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1
    "\$APP_DIR/venv/bin/pip" install -r requirements.txt > /dev/null 2>&1
fi

# Start service
echo "Starting \$APP_NAME service..."
systemctl start \$APP_NAME.service

# Check service status
echo "Waiting for service to initialize..."
sleep 3

if ! systemctl is-active --quiet \$APP_NAME.service; then
    echo "Error: Service failed to start"
    echo "Recent logs:"
    journalctl -u \$APP_NAME.service -n 20 --no-pager
    exit 1
fi

echo "✓ Service \$APP_NAME is running"

# Additional checks for web applications
if [ "\$APP_TYPE" = "web" ]; then
    echo "Running web app validation checks..."

    # Extract actual port from app logs
    sleep 2  # Give app time to bind to port
    ACTUAL_PORT=\$(journalctl -u \$APP_NAME.service -n 50 --no-pager | grep -oP '(?<=:)\d{4,5}(?=/|\s|$)' | head -1)

    if [ -z "\$ACTUAL_PORT" ]; then
        # Fallback: check for common patterns
        ACTUAL_PORT=\$(journalctl -u \$APP_NAME.service -n 50 --no-pager | grep -iE 'running on|listening on|port' | grep -oP '\d{4,5}' | head -1)
    fi

    # Verify port configuration matches
    if [ -n "\$ACTUAL_PORT" ] && [ "\$ACTUAL_PORT" != "\$WEB_PORT" ]; then
        echo "✗ ERROR: Port mismatch detected!"
        echo ""
        echo "  Configured port (WEB_PORT): \$WEB_PORT"
        echo "  Actual port from app logs:  \$ACTUAL_PORT"
        echo ""
        echo "App logs showing port:"
        journalctl -u \$APP_NAME.service -n 20 --no-pager | grep -iE 'running|listening|port|:\d{4}'
        echo ""
        echo "FIX: Update pdeploy.config to set WEB_PORT=\$ACTUAL_PORT"
        exit 1
    fi

    # Check if app is listening on the configured port
    if netstat -tuln 2>/dev/null | grep -q ":\$WEB_PORT " || ss -tuln 2>/dev/null | grep -q ":\$WEB_PORT "; then
        echo "✓ App is listening on port \$WEB_PORT"
    else
        echo "✗ WARNING: App is NOT listening on port \$WEB_PORT"
        echo ""
        echo "Checking what ports are in use:"
        netstat -tuln 2>/dev/null | grep LISTEN | grep -E ':(80|443|[0-9]{4})' || ss -tuln 2>/dev/null | grep LISTEN
        echo ""
        echo "ERROR: App failed to bind to expected port!"
        exit 1
    fi

    # Test if backend responds
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:\$WEB_PORT/ 2>/dev/null | grep -q "^[2345]"; then
        echo "✓ Backend responds on http://localhost:\$WEB_PORT/"
    else
        echo "⚠ WARNING: Backend doesn't respond (may still be initializing)"
    fi

    # Check Traefik status
    if docker ps | grep -q traefik; then
        echo "✓ Traefik reverse proxy is running"

        # Verify Traefik config exists
        if [ -f "/opt/traefik/dynamic/\$APP_NAME.yml" ]; then
            echo "✓ Traefik configuration found"
        else
            echo "✗ WARNING: Traefik config missing at /opt/traefik/dynamic/\$APP_NAME.yml"
        fi
    else
        echo "✗ WARNING: Traefik container is not running"
        echo "  Try: docker restart traefik"
    fi
fi

echo ""
echo "Deployment validation complete!"
EOF

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment initialization completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Application: $APP_NAME"
echo "Status: Running"
if [ "$APP_TYPE" = "web" ]; then
    echo "URL: https://$WEB_DOMAIN"
    echo -e "${YELLOW}Note: DNS must point to $SERVER for SSL to work${NC}"
fi
echo ""
echo "Next Steps:"
echo "  - Update your app: ./pdeploy.sh"
echo "  - Install Cockpit (web-based server management): ./cockpit-init.sh"
echo "  - Diagnostics: ./diagnose.sh"
echo -e "${GREEN}========================================${NC}"
