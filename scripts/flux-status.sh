#!/bin/bash

# flux-status.sh - A script to provide a colorized status of FluxCD components

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Gathering FluxCD Status...${NC}"
echo "--------------------------------------------------"

echo -e "\n${GREEN}1. Sources (GitRepositories)${NC}"
kubectl get gitrepositories -A

echo -e "\n${GREEN}2. Sources (HelmRepositories)${NC}"
kubectl get helmrepositories -A

echo -e "\n${GREEN}3. Kustomizations${NC}"
kubectl get kustomizations -A --sort-by=.metadata.name

echo -e "\n${GREEN}4. HelmReleases${NC}"
kubectl get helmreleases -A --sort-by=.metadata.name

echo -e "\n${GREEN}5. Suspended Resources${NC}"
echo "Kustomizations:"
kubectl get kustomizations -A -o json | jq -r '.items[] | select(.spec.suspend==true) | .metadata.name' || echo "None"
echo "HelmReleases:"
kubectl get helmreleases -A -o json | jq -r '.items[] | select(.spec.suspend==true) | .metadata.name' || echo "None"

echo "--------------------------------------------------"
echo -e "${YELLOW}Done.${NC}"
