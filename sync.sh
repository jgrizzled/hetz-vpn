#!/usr/bin/env bash
set -e
terraform apply
HOST=$(terraform output -raw public_ipv4)
VPN_PORT=$(terraform output -raw vpn_port)
ansible-playbook -i $HOST, -u admin -e "vpn_port=$VPN_PORT" sync.yaml