#!/bin/bash

home_dir="homelab-setup"
RESOLVED_CONF="/etc/systemd/resolved.conf"


sudo cp "$RESOLVED_CONF" "${RESOLVED_CONF}.bak" 2>/dev/null || true
# Update or add DNSStubListener
if sudo grep -q '^DNSStubListener=' "$RESOLVED_CONF"; then
    # Update existing entry
    sudo sed -i 's/^DNSStubListener=.*/DNSStubListener=no/' "$RESOLVED_CONF"
else
    # Add new entry at end of file
    echo "DNSStubListener=no" | sudo tee -a "$RESOLVED_CONF" >/dev/null
fi
sudo rm -rf /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart systemd-resolved 

# Uninstall Old Docker
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg >/dev/null ; done

# Installing Docker
# Add Docker's official GPG key:
sudo apt-get update >/dev/null
sudo apt-get install ca-certificates curl -y 
sudo install -m 0755 -d /etc/apt/keyrings >/dev/null
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc >/dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc >/dev/null

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Added User to Docker Group
sudo usermod -aG docker $USER


# Pihole 
sudo mkdir -p /var/lib/pihole >/dev/null
sudo cp ${home_dir}/files/pihole/compose.yaml /var/lib/pihole/compose.yaml 
sudo chown root:root /var/lib/pihole/compose.yaml
sudo cp ${home_dir}/files/pihole/pihole.service /etc/systemd/system/pihole.service
sudo chown root:root /etc/systemd/system/pihole.service

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now pihole.service
sudo systemctl restart pihole.service
