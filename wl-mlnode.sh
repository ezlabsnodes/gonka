#!/bin/bash

# Install deps
DEBIAN_FRONTEND=noninteractive apt-get install -y git pipx iptables-persistent

# Get inputs
read -p "IP VPS CPU: " CHAIN_NODE_IP
EXT_IF=$(ip route get 8.8.8.8 | awk '{print $5}')

# Setup firewall for both ports
iptables -I DOCKER-USER 1 -i "$EXT_IF" -s "$CHAIN_NODE_IP" -p tcp --dport 5050 -j RETURN
iptables -I DOCKER-USER 2 -i "$EXT_IF" -p tcp --dport 5050 -j DROP
iptables -I DOCKER-USER 3 -i "$EXT_IF" -s "$CHAIN_NODE_IP" -p tcp --dport 8080 -j RETURN
iptables -I DOCKER-USER 4 -i "$EXT_IF" -p tcp --dport 8080 -j DROP
iptables -I DOCKER-USER 5 -m state --state ESTABLISHED,RELATED -j RETURN

# Save
netfilter-persistent save 2>/dev/null || true

echo "Firewall set: Ports 5050 & 8080 whitelisted for $CHAIN_NODE_IP"
