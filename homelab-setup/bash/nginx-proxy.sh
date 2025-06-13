#!/bin/bash

home_dir="homelab-setup"

# Pihole 
sudo mkdir -p /var/lib/nginx >/dev/null
sudo cp ${home_dir}/files/nginx/compose.yaml /var/lib/nginx/compose.yaml || exit 0
sudo chown root:root /var/lib/nginx/compose.yaml

sudo cp ${home_dir}/files/nginx/nginx.conf /var/lib/nginx/nginx.conf
sudo chown root:root /var/lib/nginx/nginx.conf

sudo cp ${home_dir}/files/nginx/nginx.service /etc/systemd/system/nginx.service
sudo chown root:root /etc/systemd/system/nginx.service

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now nginx.service
sudo systemctl restart nginx.service
