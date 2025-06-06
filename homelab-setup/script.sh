#!/bin/bash

ansible-playbook master.yml --extra-vars "@vars.yml"
