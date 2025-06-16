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


# Figlet and Nvim
ssh "$SERVER" "if ! which figlet >/dev/null 2>&1; then sudo apt install figlet -y >/dev/null ;fi"
ssh "$SERVER" "if ! which nvim >/dev/null 2>&1; then sudo snap install nvim --classic >/dev/null ;fi"


install_tools() {
  local tool=$1

  DIRECTORY="homelab-setup"
  ssh "$SERVER" "if [ ! -d '$DIRECTORY' ]; then mkdir $DIRECTORY; fi"
  scp -r . "$SERVER:~/homelab-setup/." >/dev/null

  figlet "Installing $tool"
  ssh "$SERVER" "chmod +x ~/homelab-setup/${tool}.sh"
  ssh -t "$SERVER" "bash ~/homelab-setup/${tool}.sh"
}

PRIVATE_KEY="empty"
PUBLIC_KEY="empty"
setup_sops() {
  if ! which sops >/dev/null 2>&1;
  then
    curl -LO https://github.com/getsops/sops/releases/download/v3.10.2/sops-v3.10.2.linux.amd64
    sudo mv sops-v3.10.2.linux.amd64 /usr/local/bin/sops
    sudo chmod +x /usr/local/bin/sops
  fi

  if ! which sops >/dev/null 2>&1;
  then
    wget https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz
    tar -xzvf age-v1.2.1-linux-amd64.tar.gz
    chmod +x age/age 
    chmod +x age/age-keygen
    sudo mv age/age /usr/local/bin/
    sudo mv age/age-keygen /usr/local/bin/
    rm -rf age age-v1.2.1-linux-amd64.tar.gz 
  fi

  age-keygen -o age.agekey
  cat age.agekey | grep "public key:" | awk '{print $4}' > ../clusters/development/age.pubkey
}


if [[ "y" == $K8S ]]; then
  echo "  "
  read -p "Create Public and Private Key for SOPS (y/n): " SOPS

  if [[ "y" == $SOPS ]]; then
    setup_sops
  fi

  install_tools "k8s"
fi

if [[ "y" == $PIHOLE ]]; then
  install_tools "pihole"
fi

if [[ "y" == $NGINX ]]; then
  install_tools "nginx-proxy"
fi

rm -rf age.agekey
