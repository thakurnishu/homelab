#!/bin/bash

# Expected parent directory name
EXPECTED_PARENT="homelab"

CURRENT_DIR="$(basename "$PWD")"

if [[ "$CURRENT_DIR" != "$EXPECTED_PARENT" ]]; then
  echo "❌ Error: This script must be run from the '$EXPECTED_PARENT' directory"
  echo "✔️  Correct usage: bash homelab-setup/sops-setup.sh"
  exit 1
fi


PRIVATE_KEY="empty"
PUBLIC_KEY="empty"
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
  yq -i ".creation_rules[0].key_groups[0].age[0] = \"$age_public_key\"" .sops.yaml
}


setup_sops
# Create Namespace for fluxcd
kubectl create ns flux-system

cat age.agekey |
  kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin 

rm -rf age.agekey
