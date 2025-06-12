#!/bin/bash

ansible-playbook master.yaml --extra-vars "@vars.yaml"
