#!/bin/bash
# VPN 8 Automated Remote Deployment Script
# Deploys a TUN-based VPN server with NAT and all-protocol support.
set -e

# Read arguments with defaults
VPN_PORT=${1:-51820}
API_PORT=${2:-8080}
API_KEY=${3:-"vpn8_admin_default_token_9988"}
VPN_PSK=${4:-"43484f4f53455f415f5345435552455f50534b5f4b45595f544f5f5553455f38"}
VPN_SUBNET=${5:-"10.8.0.0/16"}

echo "========================================="
echo "       VPN 8 Server Installer            "
echo "========================================="
echo "Targeting UDP Port: $VPN_PORT"
echo "Targeting API Port: $API_PORT"
echo "VPN Subnet: $VPN_SUBNET"

# 1. Install Docker Engine if missing
if ! [ -x "$(command -v docker)" ]; then
    echo "[-] Installing Docker Engine..."
    curl -fsSL https://get.docker.com | sh
fi

# 2. Install Docker Compose if missing
if ! docker compose version >/dev/null 2>&1; then
    echo "[-] Installing Docker Compose plugin..."
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update
        apt-get install -y docker-compose-plugin
    elif [ -x "$(command -v yum)" ]; then
        yum install -y docker-compose-plugin
    fi
fi

# 3. Create target configuration directories
mkdir -p /opt/vpn8/data

# 4. Verify and provision Virtual TUN adapter node
if [ ! -c /dev/net/tun ]; then
    echo "[-] Virtual TUN adapter node is missing. Provisioning..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# 5. Enable Host IPv4 Forwarding (Critical for TUN-based NAT routing)
echo "[-] Enabling kernel IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# 6. Detect outbound network interface for NAT
OUT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
if [ -z "$OUT_IFACE" ]; then
    OUT_IFACE="eth0"
fi
echo "[-] Detected outbound interface: $OUT_IFACE"

# 7. Generate Docker Compose Deployment file
echo "[-] Writing Compose configuration to /opt/vpn8/docker-compose.yml..."
cat <<EOF > /opt/vpn8/docker-compose.yml
version: '3.8'

services:
  vpn8-server:
    image: ghcr.io/user/vpn8-server:latest
    container_name: vpn8-server
    restart: always
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    network_mode: host
    environment:
      - VPN_ADDR=:$VPN_PORT
      - API_ADDR=:$API_PORT
      - API_KEY=$API_KEY
      - VPN_PSK=$VPN_PSK
      - VPN_SUBNET=$VPN_SUBNET
      - TUN_NAME=vpn8-tun0
      - ENABLE_NAT=true
      - OUT_IFACE=$OUT_IFACE
      - MAX_CLIENTS=0
      - DB_PATH=/app/data/vpn8.db
    volumes:
      - ./data:/app/data
    sysctls:
      - net.ipv4.ip_forward=1
EOF

# 8. Start containerized server
echo "[-] Bootstrapping containerized VPN 8 service..."
cd /opt/vpn8

# Note: In production, the client can push a compiled Docker image,
# build it locally, or pull it from a registry. We attempt a pull.
docker compose pull || true
docker compose up -d

# 9. Set up UFW firewall rules
if [ -x "$(command -v ufw)" ]; then
    echo "[-] Restricting UFW firewall..."
    ufw allow 22/tcp || true           # SSH access
    ufw allow $VPN_PORT/udp || true    # Obfuscated VPN UDP port
    ufw allow $API_PORT/tcp || true    # Secured REST API Port
    ufw --force enable
fi

echo "========================================="
echo "   VPN 8 Installation Completed!         "
echo "========================================="
echo ""
echo "  VPN Port:     $VPN_PORT/udp"
echo "  API Port:     $API_PORT/tcp"
echo "  Subnet:       $VPN_SUBNET"
echo "  NAT via:      $OUT_IFACE"
echo ""
echo "  Default owner key: epn_owner_key_default"
echo "  (Change this immediately in production!)"
echo "========================================="
