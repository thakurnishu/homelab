#!/bin/bash

home_dir="homelab-setup"
pihole_domain="pihole.nishantlabs.cloud"
email="nishantsingh.work.503@gmail.com"

# Pihole 
sudo mkdir -p /var/lib/nginx >/dev/null
sudo cp -r ${home_dir}/files/nginx/* /var/lib/nginx/. || exit 0
sudo chown -R root:root /var/lib/nginx

sudo cp ${home_dir}/files/nginx/nginx-proxy.service /etc/systemd/system/nginx-proxy.service
sudo chown root:root /etc/systemd/system/nginx-proxy.service


sudo docker run --rm \
  --network host \
  -v "$(pwd)/certbot/www:/var/www/certbot" \
  -v "$(pwd)/certbot/conf:/etc/letsencrypt" \
  certbot/certbot certonly \
  --webroot -w /var/www/certbot \
  -d ${pihole_domain} \
  --email ${email} --agree-tos --no-eff-email


sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now nginx-proxy.service
sudo systemctl restart nginx-proxy.service
