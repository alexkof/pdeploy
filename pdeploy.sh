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

if [ -z "$SERVER" ]; then
    echo -e "${RED}Error: SERVER is required${NC}"
    exit 1
fi

# Set defaults
SSH_USER=${SSH_USER:-root}
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

# Expand SSH key path
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo -e "${GREEN}Starting deployment for $APP_NAME${NC}"
echo "Server: $SERVER"
echo "User: $SSH_USER"

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to server via SSH${NC}"
    exit 1
fi
echo -e "${GREEN}SSH connection successful${NC}"

# Stop the service
echo -e "${YELLOW}Stopping $APP_NAME service...${NC}"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
set -e
APP_NAME="$APP_NAME"

if systemctl is-active --quiet \$APP_NAME.service; then
    systemctl stop \$APP_NAME.service
    echo "Service stopped"
else
    echo "Service was not running"
fi
EOF

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
APP_DIR="/opt/apps/\$APP_NAME"

cd "\$APP_DIR"

# Install/update dependencies if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "Updating Python dependencies..."
    "\$APP_DIR/venv/bin/pip" install --upgrade pip > /dev/null 2>&1
    "\$APP_DIR/venv/bin/pip" install -r requirements.txt > /dev/null 2>&1
fi

# Start service
echo "Starting \$APP_NAME service..."
systemctl start \$APP_NAME.service

# Check service status
sleep 2
if systemctl is-active --quiet \$APP_NAME.service; then
    echo "Service \$APP_NAME is running successfully!"
    exit 0
else
    echo "Error: Service failed to start"
    echo "Recent logs:"
    journalctl -u \$APP_NAME.service -n 20 --no-pager
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Application: $APP_NAME"
    echo "Status: Running"
    echo -e "${GREEN}========================================${NC}"
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Deployment failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo "Check the logs above for details"
    exit 1
fi
