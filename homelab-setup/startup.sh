#!/bin/bash

read -p "Setup K8S Cluster(y/n): " K8S

PRIVATE_KEY="empty"
PUBLIC_KEY="empty"


install_tools() {
  local tool=$1

  DIRECTORY="homelab-setup"
  ssh "$SERVER" "if [ ! -d '$DIRECTORY' ]; then mkdir $DIRECTORY; fi"
  scp -r . "$SERVER:~/homelab-setup/." >/dev/null

  figlet "Installing $tool"
  ssh "$SERVER" "chmod +x ~/homelab-setup/${tool}.sh"
  ssh -t "$SERVER" "bash ~/homelab-setup/${tool}.sh"
}


setup_sops() {
  if ! which sops >/dev/null 2>&1;
  then
    curl -LO https://github.com/getsops/sops/releases/download/v3.10.2/sops-v3.10.2.linux.amd64
    sudo mv sops-v3.10.2.linux.amd64 /usr/local/bin/sops
    sudo chmod +x /usr/local/bin/sops
  fi

  if ! which age >/dev/null 2>&1;
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


if [[ "y" == $K8S ]]; then
  echo "  "
  read -p "Create Public and Private Key for SOPS (y/n): " SOPS

  if [[ "y" == $SOPS ]]; then
    setup_sops
    # Create Namespace for fluxcd
    kubectl create ns flux-system

    cat age.agekey |
    kubectl create secret generic sops-age \
      --namespace=flux-system \
      --from-file=age.agekey=/dev/stdin 
  fi

  bash ./k8s.sh
fi

rm -rf age.agekey
