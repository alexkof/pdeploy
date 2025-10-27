#!/bin/bash

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Cockpit Installation and Configuration${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo "This script will:"
echo "  - Install Cockpit web-based server management UI"
echo "  - Optionally create an admin user for Cockpit access"
echo "  - Optionally disable SSH password authentication (key-only)"
echo ""

# Get server details
read -p "Server IP or hostname: " SERVER
if [ -z "$SERVER" ]; then
    echo -e "${RED}Error: Server is required${NC}"
    exit 1
fi

read -p "SSH user [default: root]: " SSH_USER
SSH_USER=${SSH_USER:-root}

read -p "SSH key path [default: ~/.ssh/id_rsa]: " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

# Expand SSH key path
SSH_KEY="${SSH_KEY/#\~/$HOME}"

echo ""
echo "Server: $SERVER"
echo "User: $SSH_USER"
echo "SSH Key: $SSH_KEY"
echo ""

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER" "echo 'SSH OK'" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to server via SSH${NC}"
    exit 1
fi
echo -e "${GREEN}SSH connection successful${NC}"
echo ""

# Ask about Cockpit password setup
echo -e "${YELLOW}Admin User Configuration:${NC}"
echo ""
read -p "Do you want to create an admin user for Cockpit and disable SSH password authentication? [y/N]: " -n 1 -r
echo ""

SETUP_COCKPIT_PASSWORD="no"
COCKPIT_USER_PASSWORD=""
COCKPIT_USERNAME=""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "This will:"
    echo "  1. Create a new admin user (with sudo access)"
    echo "  2. Set a password for Cockpit login"
    echo "  3. Disable SSH password authentication (keys only)"
    echo "  4. Keep your SSH key authentication working"
    echo ""

    # Ask for username
    while true; do
        read -p "Enter username for admin user [default: admin]: " COCKPIT_USERNAME
        COCKPIT_USERNAME=${COCKPIT_USERNAME:-admin}

        # Validate username
        if [[ "$COCKPIT_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        else
            echo -e "${RED}Invalid username. Use lowercase letters, numbers, underscore, hyphen only.${NC}"
        fi
    done

    # Ask for password
    while true; do
        read -sp "Enter password for user '$COCKPIT_USERNAME': " COCKPIT_USER_PASSWORD
        echo ""
        read -sp "Confirm password: " COCKPIT_USER_PASSWORD_CONFIRM
        echo ""

        if [ "$COCKPIT_USER_PASSWORD" = "$COCKPIT_USER_PASSWORD_CONFIRM" ]; then
            if [ -n "$COCKPIT_USER_PASSWORD" ]; then
                SETUP_COCKPIT_PASSWORD="yes"
                echo -e "${GREEN}User '$COCKPIT_USERNAME' will be created${NC}"
                break
            else
                echo -e "${RED}Password cannot be empty. Try again.${NC}"
            fi
        else
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        fi
    done
else
    echo -e "${YELLOW}Skipping admin user setup. You can create one later manually.${NC}"
fi

# Install Cockpit on server
echo ""
echo -e "${YELLOW}Installing Cockpit on server...${NC}"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER" "bash -s" << EOF
set -e

SETUP_COCKPIT_PASSWORD="$SETUP_COCKPIT_PASSWORD"
COCKPIT_USER_PASSWORD="$COCKPIT_USER_PASSWORD"
COCKPIT_USERNAME="$COCKPIT_USERNAME"

echo "Updating package list..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# Install Cockpit
echo "Installing Cockpit..."
apt-get install -y -qq cockpit cockpit-podman > /dev/null 2>&1 || apt-get install -y -qq cockpit > /dev/null

# Enable Cockpit service
systemctl enable --now cockpit.socket > /dev/null 2>&1

# Allow Cockpit through UFW if it's active
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 9090/tcp > /dev/null 2>&1 || true
fi

SERVER_IP=\$(hostname -I | awk '{print \$1}')
echo "Cockpit installed and accessible at https://\$SERVER_IP:9090"

# Configure admin user and SSH security if requested
if [ "\$SETUP_COCKPIT_PASSWORD" = "yes" ]; then
    echo "Configuring admin user and SSH security..."

    # Create admin user if it doesn't exist
    if ! id "\$COCKPIT_USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash "\$COCKPIT_USERNAME"
        echo "Created user \$COCKPIT_USERNAME"
    else
        echo "User \$COCKPIT_USERNAME already exists"
    fi

    # Set password for the admin user
    echo "\$COCKPIT_USERNAME:\$COCKPIT_USER_PASSWORD" | chpasswd
    echo "Password set for user \$COCKPIT_USERNAME"

    # Add user to sudo group
    usermod -aG sudo "\$COCKPIT_USERNAME"
    echo "User \$COCKPIT_USERNAME added to sudo group"

    # Disable SSH password authentication (force key-only)
    sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

    # Ensure these settings are in the config if not present
    grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
    grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config

    # Restart SSH service (Ubuntu uses 'ssh' not 'sshd')
    systemctl restart ssh || systemctl restart sshd
    echo "SSH password authentication disabled - key-only access configured"
fi

echo ""
echo "Cockpit installation complete!"
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cockpit Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Access Cockpit at: https://$SERVER:9090"
echo ""

if [ "$SETUP_COCKPIT_PASSWORD" = "yes" ]; then
    echo "Login credentials:"
    echo "  Username: $COCKPIT_USERNAME"
    echo "  Password: [the password you set]"
    echo ""
    echo -e "${GREEN}✓ Admin user created with sudo access${NC}"
    echo -e "${GREEN}✓ SSH password authentication disabled (key-only)${NC}"
else
    echo "To create an admin user later:"
    echo "  ssh $SSH_USER@$SERVER 'adduser admin && usermod -aG sudo admin'"
fi
echo ""
echo "Tunnel access (if port 9090 is blocked):"
echo "  ./cockpit-tunnel.sh"
echo -e "${GREEN}========================================${NC}"
