#!/bin/bash

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
  if ! which yq >/dev/null 2>&1;
  then
    sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
    sudo chmod +x /usr/local/bin/yq
  fi

  age-keygen -o age.agekey
  age_public_key=$(cat age.agekey | grep "public key:" | awk '{print $4}')
  yq -i ".creation_rules[0].key_groups[0].age[0] = \"$age_public_key\"" ../.sops.yaml
}


echo "  "
read -p "Create Public and Private Key for SOPS (y/n): " SOPS

if [[ "y" == $SOPS ]]; then
  setup_sops
fi

rm -rf age.agekey
