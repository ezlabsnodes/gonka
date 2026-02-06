#!/bin/bash

# =========================
#  GONKA CHAIN NODE ONE-CLICK
#  VPS WITHOUT GPU (tmkms + node + api)
#  HOT & COLD WALLET (CREATE/IMPORT)
# =========================

# Output Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA CHAIN NODE AUTO-INSTALLER (SERVER-CPU) ===${NC}"

# 1. Environment Setup (light, assumes Docker is already installed)
echo -e "${YELLOW}[1/11] Preparing environment (unzip, etc)...${NC}"
sudo apt update && sudo apt install -y unzip
export PATH="$HOME/.local/bin:$PATH"

# 2. Download Wallet Binary & HOT WALLET (gonka-account-key)
echo -e "${YELLOW}[2/11] Downloading wallet binary & setting up HOT wallet...${NC}"

if [ ! -f "./inferenced" ]; then
  wget -q -O inferenced-linux-amd64.zip "https://github.com/gonka-ai/gonka/releases/download/release%2Fv0.2.9/inferenced-linux-amd64.zip"
  unzip -o inferenced-linux-amd64.zip && chmod +x inferenced
fi

echo -e "${GREEN}HOT Wallet Option (gonka-account-key):${NC}"
echo "1. Create new HOT wallet"
echo "2. Import existing HOT wallet (mnemonic)"
read -p "Selection (1/2): " hot_choice

if [ "$hot_choice" == "2" ]; then
    echo -e "${YELLOW}Importing HOT wallet (paste mnemonic in CLI prompt)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file --recover)
else
    echo -e "${YELLOW}Creating new HOT wallet gonka-account-key (follow password prompt & save mnemonic)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file)
fi

echo "$WALLET_DATA"

# Extract Address & PubKey from HOT wallet
ACCOUNT_ADDRESS=$(echo "$WALLET_DATA" | grep -oP 'gonka1[a-z0-9]+' | head -n 1)
ACCOUNT_PUBKEY=$(echo "$WALLET_DATA" | grep -oP '"key":"\K[^"]+' | head -n 1)

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$ACCOUNT_PUBKEY" ]; then
  echo -e "${RED}Failed to parse ACCOUNT_ADDRESS or ACCOUNT_PUBKEY from HOT wallet output.${NC}"
  exit 1
fi

echo -e "${GREEN}Main Wallet Address (HOT):${NC} $ACCOUNT_ADDRESS"
echo -e "${GREEN}Account PubKey (HOT, from step 2):${NC} $ACCOUNT_PUBKEY"

export ACCOUNT_ADDRESS
export ACCOUNT_PUBKEY

# 2b. Set KEYRING_PASSWORD for ml-ops-key
echo
echo -e "${YELLOW}[2b] Set KEYRING_PASSWORD for ML Ops (COLD wallet / ml-ops-key)...${NC}"
echo -e "${GREEN}NOTE: This password MUST match the passphrase you enter inside the api container later.${NC}"
read -s -p "Set KEYRING_PASSWORD (for ml-ops-key, do not use spaces): " KEYRING_PASSWORD
echo

echo -e "${GREEN}COLD Wallet Option (ML Ops / ml-ops-key):${NC}"
echo "1. Create new COLD wallet (ml-ops-key)"
echo "2. Import existing COLD wallet (mnemonic ml-ops-key)"
read -p "Selection (1/2): " cold_choice

# 3. Download Gonka & Prepare Directory
echo -e "${YELLOW}[3/11] Cloning repository & preparing directories...${NC}"
if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Failed to cd into gonka/deploy/join${NC}"; exit 1; }

cp config.env.template config.env
mkdir -p /mnt/shared

# 4. Modifying config.env (CHAIN VPS)
echo -e "${YELLOW}[4/11] Modifying config.env...${NC}"

IPV4=$(curl -4 -s ifconfig.me)

# KEY_NAME fixed for ML Ops
KEY_NAME="ml-ops-key"

# Set KEY_NAME & KEYRING_PASSWORD
sed -i "s|export KEY_NAME=.*|export KEY_NAME=$KEY_NAME|g" config.env
sed -i "s|export KEYRING_PASSWORD=.*|export KEYRING_PASSWORD=$KEYRING_PASSWORD|g" config.env

# PUBLIC_URL & P2P_EXTERNAL_ADDRESS use this CHAIN VPS IP
sed -i "s|export PUBLIC_URL=.*|export PUBLIC_URL=http://$IPV4:8000|g" config.env
sed -i "s|export P2P_EXTERNAL_ADDRESS=.*|export P2P_EXTERNAL_ADDRESS=tcp://$IPV4:5000|g" config.env

# IMPORTANT: ACCOUNT_PUBKEY uses PUBKEY from HOT wallet (not address)
sed -i "s|export ACCOUNT_PUBKEY=.*|export ACCOUNT_PUBKEY=$ACCOUNT_PUBKEY|g" config.env

# SEED API URL
sed -i "s|export SEED_API_URL=.*|export SEED_API_URL=http://node1.gonka.ai:8000|g" config.env

# IMPORTANT: this is the API URL on CHAIN VPS that can be reached by GPU SERVER
# callback port 9100
sed -i "s|export DAPI_API__POC_CALLBACK_URL=.*|export DAPI_API__POC_CALLBACK_URL=http://$IPV4:9100|g" config.env

# Load env
source config.env

# 5. Empty node-config.json (no local ML node)
echo -e "${YELLOW}[5/11] Writing empty node-config.json (no local ML node)...${NC}"

cat > node-config.json << 'EOF'
[]
EOF

# 6. Skip HF CLI & model download (VPS without GPU)
echo -e "${YELLOW}[6/11] Skipping HF CLI & model download (not needed on CHAIN VPS)...${NC}"

# 7. Pull Containers (only docker-compose.yml)
echo -e "${YELLOW}[7/11] Pulling Docker images (tmkms + node + api)...${NC}"
docker compose -f docker-compose.yml pull

# 8. Start tmkms + node + api
echo -e "${YELLOW}[8/11] Starting tmkms, node, and api...${NC}"
source config.env
docker compose up tmkms node api -d --no-deps

# 9. COLD WALLET (ml-ops-key) + Register Host
echo -e "${YELLOW}[9/11] Setting up COLD wallet (ml-ops-key) inside api container...${NC}"
echo -e "${GREEN}NOTE: When prompted 'Enter keyring passphrase', use the same KEYRING_PASSWORD you set above.${NC}"

if [ "$cold_choice" == "2" ]; then
  echo -e "${YELLOW}>> IMPORT COLD WALLET MODE (ml-ops-key) <<${NC}"
  echo -e "${YELLOW}Inside the container you will:${NC}"
  echo -e "  - Enter keyring passphrase (same as KEYRING_PASSWORD)"
  echo -e "  - Re-enter passphrase"
  echo -e "  - Paste mnemonic for ml-ops-key"
  docker compose run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file --recover
else
  echo -e "${YELLOW}>> CREATE COLD WALLET MODE (ml-ops-key) <<${NC}"
  echo -e "${YELLOW}Inside the container you will:${NC}"
  echo -e "  - Enter keyring passphrase (same as KEYRING_PASSWORD)"
  echo -e "  - Re-enter passphrase"
  echo -e "  - SAVE the mnemonic for ml-ops-key that is displayed!"
  docker compose run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file
fi

# After leaving the container, fetch ml-ops-key address non-interactively
echo -e "${YELLOW}Fetching ML Ops address from keyring inside the container...${NC}"

ML_OPS_ADDRESS=$(docker compose run --rm --no-deps \
  -e KEY_NAME="$KEY_NAME" -e KEYRING_PASSWORD="$KEYRING_PASSWORD" \
  api /bin/sh -c 'printf "%s\n" "$KEYRING_PASSWORD" | inferenced keys show "$KEY_NAME" --keyring-backend file -a' \
  2>/dev/null | tr -d '\r' | tail -n 1)

if [ -z "$ML_OPS_ADDRESS" ]; then
    echo -e "${RED}Error: Failed to read ML Ops address from ml-ops-key! Make sure the passphrase matches.${NC}"
    exit 1
fi

echo -e "${GREEN}ML Operational Address (COLD / ml-ops-key):${NC} $ML_OPS_ADDRESS"

echo -e "${YELLOW}Registering host (step 9.1.2) with PUBKEY from HOT wallet (auto retry)...${NC}"

REGISTER_OK=0
for i in {1..10}; do
  if env ACCOUNT_PUBKEY="$ACCOUNT_PUBKEY" DAPI_API__PUBLIC_URL="http://$IPV4:8000" \
      docker compose run --rm --no-deps api /bin/sh -c \
      'inferenced register-new-participant "$DAPI_API__PUBLIC_URL" "$ACCOUNT_PUBKEY" --node-address http://node1.gonka.ai:8000'; then
    REGISTER_OK=1
    echo -e "${GREEN}Host registration succeeded on attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Host registration failed (attempt $i), retrying in 30 seconds...${NC}"
    sleep 30
  fi
done

if [ "$REGISTER_OK" -ne 1 ]; then
  echo -e "${RED}Failed to register host after multiple attempts. Exiting.${NC}"
  exit 1
fi

# 10. Grant Permissions to ML Operational Key
echo -e "${YELLOW}[10/11] Granting ML Ops permissions (auto retry)...${NC}"

cd ../../../ || { echo -e "${RED}Failed to cd ../../../ from gonka/deploy/join${NC}"; exit 1; }

GRANT_OK=0
for i in {1..20}; do
  if ./inferenced tx inference grant-ml-ops-permissions \
        gonka-account-key \
        "$ML_OPS_ADDRESS" \
        --from gonka-account-key \
        --keyring-backend file \
        --gas 2000000 \
        --node http://node1.gonka.ai:8000/chain-rpc/ \
        --yes; then
    GRANT_OK=1
    echo -e "${GREEN}Grant ML Ops permissions succeeded on attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Grant permissions failed (attempt $i), retrying in 30 seconds...${NC}"
    sleep 30
  fi
done

if [ "$GRANT_OK" -ne 1 ]; then
  echo -e "${RED}Failed to grant ML Ops permissions after multiple attempts.${NC}"
  # still continue starting services so the node runs, but ML ops permissions may not be active
fi

# 11. Start Full Node (tmkms + node + api)
echo -e "${YELLOW}[11/11] Launching all services (tmkms + node + api)...${NC}"
cd gonka/deploy/join || { echo -e "${RED}Failed to return to gonka/deploy/join${NC}"; exit 1; }

source config.env
docker compose up tmkms node api -d --no-deps

# Cleanup zip if it still exists
rm -f inferenced-linux-amd64.zip "$HOME/inferenced-linux-amd64.zip" 2>/dev/null || true

echo -e "${GREEN}=== CHAIN NODE INSTALLATION FINISHED (NO GPU) ===${NC}"
echo -e "Dashboard: http://$IPV4:8000/dashboard"

echo
echo -e "${YELLOW}Optional log commands:${NC}"
echo "All logs:"
echo "  cd ~/gonka/deploy/join && docker compose logs --tail 1000"
echo
echo "Chain Node:"
echo "  docker logs --tail 500 node"
echo
echo "TMKMS:"
echo "  docker logs --tail 500 tmkms"
echo
echo "API Node:"
echo "  docker logs --tail 500 api"
