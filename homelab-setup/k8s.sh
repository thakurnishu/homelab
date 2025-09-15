#!/bin/bash

git_user="thakurnishu"
git_repo="homelab"

if ! which flux >/dev/null 2>&1;
then
  echo ' '
  echo 'Installing flux ...'
  sleep 1
  curl -s https://fluxcd.io/install.sh | sudo bash
fi

if ! which k9s >/dev/null 2>&1;
then
  echo ' '
  echo 'Installing K9S...'
  sleep 1
  curl -LO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
  tar -xvf k9s_Linux_amd64.tar.gz
  rm -rf k9s_Linux_amd64.tar.gz LICENSE README.md
  sudo mv k9s /usr/local/bin/
fi


echo ' '
flux bootstrap github \
  --token-auth=false \
  --owner=${git_user} \
  --repository=${git_repo} \
  --branch=talos \
  --path=clusters/development \
  --personal --private=false \
  --read-write-key=true \
  --components-extra=image-reflector-controller,image-automation-controller
