#!/bin/bash

# Prompt for SSH server name
read -p "Enter SSH server name (default: homelab): " SERVER
read -p "Install K8S Cluster using kubeadm (y/n): " K8S
read -p "Install Pihole (y/n): " PIHOLE 
read -p "Install Nginx Proxy (y/n): " NGINX

# Check if input is empty
if [[ -z "$SERVER" ]]; then
    SERVER="homelab"
fi

# Copy script.sh to remote server
DIRECTORY="homelab-setup"
ssh "$SERVER" "if [ ! -d '$DIRECTORY' ]; then mkdir $DIRECTORY; fi"
scp -r . "$SERVER:~/homelab-setup/." >/dev/null
# Figlet
ssh "$SERVER" "if ! which figlet >/dev/null 2>&1; then sudo apt install figlet -y >/dev/null ;fi"
ssh "$SERVER" "if ! which nvim >/dev/null 2>&1; then sudo snap install nvim --classic >/dev/null ;fi"

# SSH into server and run script.sh interactively
if [[ "y" == $K8S ]]; then
  figlet "Installing K8S"
  ssh "$SERVER" "chmod +x ~/homelab-setup/k8s.sh"
  ssh -t "$SERVER" "bash ~/homelab-setup/k8s.sh"
fi

if [[ "y" == $PIHOLE ]]; then
  figlet "Installing Pihole"
  ssh "$SERVER" "chmod +x ~/homelab-setup/pihole.sh"
  ssh -t "$SERVER" "bash ~/homelab-setup/pihole.sh"
fi

if [[ "y" == $NGINX ]]; then
  figlet "Installing Nginx"
  ssh "$SERVER" "chmod +x ~/homelab-setup/nginx-proxy.sh"
  ssh -t "$SERVER" "bash ~/homelab-setup/nginx-proxy.sh"
fi
