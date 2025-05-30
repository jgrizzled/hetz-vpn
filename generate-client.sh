#!/usr/bin/env bash
set -e

# Script to generate a new Wireguard client configuration

if [ $# -ne 2 ]; then
    echo "Usage: $0 <client-name> <client-ip>"
    echo "Example: $0 john-laptop 10.0.0.2"
    echo ""
    echo "Available IPs: 10.0.0.2 - 10.0.0.254"
    echo "Server uses: 10.0.0.1"
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_IP="$2"

# Check if server public key exists
if [ ! -f "server_public.key" ]; then
    echo "Error: server_public.key not found. Run ./bootstrap.sh first."
    exit 1
fi

# Get server public IP and port
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform not found. Please install terraform."
    exit 1
fi

SERVER_PUBLIC_IP=$(terraform output -raw public_ipv4 2>/dev/null || echo "")
SERVER_VPN_PORT=$(terraform output -raw vpn_port 2>/dev/null || echo "51820")
if [ -z "$SERVER_PUBLIC_IP" ]; then
    echo "Error: Could not get server public IP. Make sure terraform has been applied."
    exit 1
fi

SERVER_PUBLIC_KEY=$(cat server_public.key)

# Generate client keys
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

# Create client config file
cat > "${CLIENT_NAME}.conf" << EOF
[Interface]
# Client private key
PrivateKey = $CLIENT_PRIVATE_KEY
# Client IP address in the VPN network
Address = $CLIENT_IP/32
# DNS servers to use when connected
DNS = 1.1.1.1, 8.8.8.8

[Peer]
# Server public key
PublicKey = $SERVER_PUBLIC_KEY
# Server endpoint
Endpoint = $SERVER_PUBLIC_IP:$SERVER_VPN_PORT
# Route all traffic through VPN (change to specific subnets if needed)
AllowedIPs = 0.0.0.0/0, ::/0
# Keep connection alive
PersistentKeepalive = 25
EOF

echo "Generated client configuration: ${CLIENT_NAME}.conf"
echo ""
echo "Client Public Key: $CLIENT_PUBLIC_KEY"
echo ""

# Check if wg0.conf exists
if [ ! -f "wg0.conf" ]; then
    echo "Error: wg0.conf not found. Make sure the server has been set up."
    exit 1
fi

# Append peer configuration to wg0.conf
echo "" >> wg0.conf
echo "[Peer]" >> wg0.conf
echo "PublicKey = $CLIENT_PUBLIC_KEY" >> wg0.conf
echo "AllowedIPs = $CLIENT_IP/32" >> wg0.conf

echo "Added peer configuration to wg0.conf"
echo "Run ./sync.sh to update the server configuration." 