#!/bin/bash

# Prompt for SSH server name
read -p "Enter SSH server name (default: homelab): " SERVER

# Check if input is empty
if [[ -z "$SERVER" ]]; then
    SERVER="homelab"
fi

# Copy script.sh to remote server
echo "Copying $SCRIPT to $SERVER..."
ssh "$SERVER" "mkdir homelab-setup"
scp -r . "$SERVER:~/homelab-setup/."

# SSH into server and run script.sh interactively
echo "Connecting to $SERVER and running $SCRIPT..."
ssh "$SERVER" "chmod +x ~/homelab-setup/setup.sh"
ssh -t "$SERVER" "bash ~/homelab-setup/setup.sh"
