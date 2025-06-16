#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

while IFS= read -r path; do
    path=${path/.sops/ }
    find . -regextype egrep -regex ".*/$path" -type f | while IFS= read -r file; do

        encrypted_file="${file%.yaml}.sops.yaml"

        # No encrypted version exists, encrypt the file
        echo -e "${RED}Encrypting file: $file${NC}"
        sops --encrypt "$file" >"$encrypted_file"
    done
done < <(grep -oP '^\s*- path_regex:\s*\K.*' ".sops.yaml")
