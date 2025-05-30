#!/usr/bin/env bash
set -e
terraform apply
IP=$(terraform output -raw public_ipv4)
VPN_PORT=$(terraform output -raw vpn_port)
SSH_PORT=$(terraform output -raw ssh_port)
HOST="$IP:$SSH_PORT"
ansible-playbook -i $HOST, -u admin -e "vpn_port=$VPN_PORT" sync.yaml