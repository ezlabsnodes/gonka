#!/bin/bash

# =========================
#  GONKA NODE ONE-CLICK
#  (full auto, no manual)
# =========================

# Output Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA NODE AUTO-INSTALLER ===${NC}"

# 1. Environment Setup
echo -e "${YELLOW}[1/11] Preparing Environment...${NC}"
sudo apt update && sudo apt install -y pipx unzip
export PATH="$HOME/.local/bin:$PATH"

# 2. Download Wallet Binary & Create/Import Wallet
echo -e "${YELLOW}[2/11] Downloading Wallet Binary & Create/Import Wallet...${NC}"

if [ ! -f "./inferenced" ]; then
  wget -q -O inferenced-linux-amd64.zip "https://github.com/gonka-ai/gonka/releases/download/release%2Fv0.2.6-post1/inferenced-linux-amd64.zip"
  unzip -o inferenced-linux-amd64.zip && chmod +x inferenced
fi

echo -e "${GREEN}Wallet Option:${NC}"
echo "1. Create New Wallet (gonka-account-key)"
echo "2. Import Existing Wallet (Mnemonic) as gonka-account-key"
read -p "Selection (1/2): " wallet_choice

if [ "$wallet_choice" == "2" ]; then
    echo -e "${YELLOW}Import wallet (paste mnemonic di prompt CLI)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file --recover)
else
    echo -e "${YELLOW}Membuat wallet baru gonka-account-key (ikuti prompt password dari CLI)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file)
fi

echo "$WALLET_DATA"

# Extract Address & PubKey (PUB KEY FROM STEP 2)
ACCOUNT_ADDRESS=$(echo "$WALLET_DATA" | grep -oP 'gonka1[a-z0-9]+' | head -n 1)
ACCOUNT_PUBKEY=$(echo "$WALLET_DATA" | grep -oP '"key":"\K[^"]+' | head -n 1)

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$ACCOUNT_PUBKEY" ]; then
  echo -e "${RED}Gagal parsing ACCOUNT_ADDRESS atau ACCOUNT_PUBKEY dari output wallet.${NC}"
  exit 1
fi

echo -e "${GREEN}Main Wallet Address :${NC} $ACCOUNT_ADDRESS"
echo -e "${GREEN}Account PubKey (from step 2) :${NC} $ACCOUNT_PUBKEY"

export ACCOUNT_ADDRESS
export ACCOUNT_PUBKEY

# KEY_NAME fix jadi ml-ops-key
KEY_NAME="ml-ops-key"
echo -e "${GREEN}KEY_NAME untuk ML Ops key diset ke:${NC} $KEY_NAME"

# KEYRING_PASSWORD: dipakai di dalam container saat bikin ML Ops key
read -s -p "Set KEYRING_PASSWORD (password untuk ML Ops key di container, jangan pakai spasi): " KEYRING_PASSWORD
echo

# 3. Download Gonka & Prepare Directory
echo -e "${YELLOW}[3/11] Cloning Repository & Preparing Directories...${NC}"
if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Gagal cd ke gonka/deploy/join${NC}"; exit 1; }

cp config.env.template config.env
mkdir -p /mnt/shared

# 4. Modifying config.env (ACCOUNT_PUBKEY pakai PUBKEY dari step 2)
echo -e "${YELLOW}[4/11] Modifying config.env...${NC}"

IPV4=$(curl -4 -s ifconfig.me)

# Set KEY_NAME & KEYRING_PASSWORD
sed -i "s|export KEY_NAME=.*|export KEY_NAME=$KEY_NAME|g" config.env
sed -i "s|export KEYRING_PASSWORD=.*|export KEYRING_PASSWORD=$KEYRING_PASSWORD|g" config.env

# PUBLIC_URL & P2P_EXTERNAL_ADDRESS pakai IP VPS
sed -i "s|export PUBLIC_URL=.*|export PUBLIC_URL=http://$IPV4:8000|g" config.env
sed -i "s|export P2P_EXTERNAL_ADDRESS=.*|export P2P_EXTERNAL_ADDRESS=tcp://$IPV4:5000|g" config.env

# PENTING: ACCOUNT_PUBKEY pakai PUBKEY (Axx/Atxx...) dari step 2, BUKAN address gonka1...
sed -i "s|export ACCOUNT_PUBKEY=.*|export ACCOUNT_PUBKEY=$ACCOUNT_PUBKEY|g" config.env

# SEED_API_URL sesuai instruksi
sed -i "s|export SEED_API_URL=.*|export SEED_API_URL=http://node1.gonka.ai:8000|g" config.env

# Load env
source config.env

# HF_HOME default kalau belum di-set
[ -z "$HF_HOME" ] && export HF_HOME=/mnt/shared/hf-cache
mkdir -p "$HF_HOME"

# 5. Custom node-config.json (SESUSAI YANG KAMU MAU)
echo -e "${YELLOW}[5/11] Writing custom node-config.json...${NC}"

cat <<'EOF' > node-config.json
[
    {
        "id": "node1",
        "host": "inference",
        "inference_port": 5000,
        "poc_port": 8080,
        "max_concurrent": 150,
        "models": {
            "Qwen/Qwen2.5-7B-Instruct": {
                "args": [
                    "--quantization", "fp8",
                    "--gpu-memory-utilization", "0.9"
                ]
            }
        }
    }
]
EOF

# 6. Install Hugging Face CLI dan download model weights
echo -e "${YELLOW}[6/11] Installing HF CLI & Downloading Model Weights...${NC}"

pipx install --force "huggingface_hub[cli]"
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

HF_CMD=$(command -v hf || command -v huggingface-cli || echo "$HOME/.local/bin/hf")
if [ ! -x "$HF_CMD" ]; then
    echo -e "${RED}huggingface CLI (hf) tidak ditemukan setelah install.${NC}"
    exit 1
fi

$HF_CMD download Qwen/Qwen2.5-7B-Instruct

# 7. Pull Containers
echo -e "${YELLOW}[7/11] Pulling Docker Images...${NC}"
docker compose -f docker-compose.yml -f docker-compose.mlnode.yml pull

# 8. Start Initial Services (tmkms + node)
echo -e "${YELLOW}[8/11] Starting tmkms and node...${NC}"
source config.env
docker compose up tmkms node -d --no-deps

# 9. Create ML Operational Key & Register Host
echo -e "${YELLOW}[9/11] Creating ML Operational Key inside api container...${NC}"

ML_KEY_DATA=$(env KEY_NAME="$KEY_NAME" KEYRING_PASSWORD="$KEYRING_PASSWORD" \
    docker compose run --rm --no-deps api /bin/sh -c \
    'printf "%s\n%s\n" "$KEYRING_PASSWORD" "$KEYRING_PASSWORD" | inferenced keys add "$KEY_NAME" --keyring-backend file')

echo "$ML_KEY_DATA"

# Ambil ML Ops address dari output container (ini yang nanti dipakai di step 10)
ML_OPS_ADDRESS=$(echo "$ML_KEY_DATA" | grep -oP 'gonka1[a-z0-9]+' | head -n 1)

if [ -z "$ML_OPS_ADDRESS" ]; then
    echo -e "${RED}Error: Failed to create ML Operational Key!${NC}"
    exit 1
fi

echo -e "${GREEN}ML Operational Address (from step 9.1.1):${NC} $ML_OPS_ADDRESS"

echo -e "${YELLOW}Registering Host (step 9.1.2) dengan PUBKEY dari step 2 (auto retry)...${NC}"

REGISTER_OK=0
for i in {1..10}; do
  if env ACCOUNT_PUBKEY="$ACCOUNT_PUBKEY" DAPI_API__PUBLIC_URL="http://$IPV4:8000" \
      docker compose run --rm --no-deps api /bin/sh -c \
      'inferenced register-new-participant "$DAPI_API__PUBLIC_URL" "$ACCOUNT_PUBKEY" --node-address http://node1.gonka.ai:8000'; then
    REGISTER_OK=1
    echo -e "${GREEN}Register host berhasil pada attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Register host gagal (attempt $i), retry dalam 30 detik...${NC}"
    sleep 30
  fi
done

if [ "$REGISTER_OK" -ne 1 ]; then
  echo -e "${RED}Gagal register host setelah beberapa percobaan. Keluar.${NC}"
  exit 1
fi

# 10. Grant Permissions to ML Operational Key (auto retry)
echo -e "${YELLOW}[10/11] Granting ML Ops Permissions (auto retry)...${NC}"

cd ../../../ || { echo -e "${RED}Gagal cd ../../../ dari gonka/deploy/join${NC}"; exit 1; }

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
    echo -e "${GREEN}Grant ML Ops permissions berhasil pada attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Grant permissions gagal (attempt $i), retry dalam 30 detik...${NC}"
    sleep 30
  fi
done

if [ "$GRANT_OK" -ne 1 ]; then
  echo -e "${RED}Gagal grant ML Ops permissions setelah beberapa percobaan.${NC}"
  # tetap lanjut start service supaya node jalan, tapi izin ML ops mungkin belum aktif
fi

# 11. Start Full Node
echo -e "${YELLOW}[11/11] Launching All Services...${NC}"
cd gonka/deploy/join || { echo -e "${RED}Gagal kembali ke gonka/deploy/join${NC}"; exit 1; }

source config.env
docker compose -f docker-compose.yml -f docker-compose.mlnode.yml up -d

# Cleanup zip kalau masih ada
rm -f inferenced-linux-amd64.zip "$HOME/inferenced-linux-amd64.zip" 2>/dev/null || true

echo -e "${GREEN}=== INSTALLATION FINISHED (SCRIPT FULL AUTO) ===${NC}"
echo -e "Dashboard: http://$IPV4:8000/dashboard"

echo
echo -e "${YELLOW}Commands untuk cek log (optional):${NC}"
echo "All Logs:"
echo "  cd ~/gonka/deploy/join && docker compose logs --tail 1000"
echo
echo "Chain Node:"
echo "  docker logs --tail 500 node"
echo
echo "TMKMS:"
echo "  docker logs --tail 500 tmkms"
echo
echo "ML Node:"
echo "  docker logs --tail 500 join-mlnode-308-1"
echo
echo "API Node:"
echo "  docker logs --tail 500 api"
