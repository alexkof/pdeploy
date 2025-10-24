#!/bin/bash
# Quick script to open Cockpit UI via SSH tunnel

# Load config
source pdeploy.config 2>/dev/null || { echo "Error: pdeploy.config not found"; exit 1; }

# Expand SSH key path
SSH_KEY="${SSH_KEY/#\~/$HOME}"
SSH_USER="${SSH_USER:-root}"

echo "Creating SSH tunnel to Cockpit on $SERVER..."
echo "Opening https://localhost:9090 in your browser..."
echo ""
echo "Press Ctrl+C to close the tunnel when done"
echo ""

# Open browser (works on Windows/Mac/Linux)
sleep 2 && (start http://localhost:9090 2>/dev/null || open http://localhost:9090 2>/dev/null || xdg-open http://localhost:9090 2>/dev/null) &

# Create SSH tunnel (this will run until Ctrl+C)
ssh -i "$SSH_KEY" -L 9090:localhost:9090 -N "$SSH_USER@$SERVER"
