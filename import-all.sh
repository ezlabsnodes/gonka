#!/bin/bash

# =========================
#  GONKA NODE ONE-CLICK
#  HOT & COLD: CREATE/IMPORT
# =========================

# Output Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA NODE AUTO-INSTALLER (HOT & COLD WALLET MENU) ===${NC}"

# 1. Environment Setup
echo -e "${YELLOW}[1/11] Preparing Environment...${NC}"
sudo apt update && sudo apt install -y pipx unzip
export PATH="$HOME/.local/bin:$PATH"

# 2. Download Wallet Binary & HOT WALLET (gonka-account-key)
echo -e "${YELLOW}[2/11] Downloading Wallet Binary & Setup HOT Wallet...${NC}"

if [ ! -f "./inferenced" ]; then
  wget -q -O inferenced-linux-amd64.zip "https://github.com/gonka-ai/gonka/releases/download/release%2Fv0.2.6-post1/inferenced-linux-amd64.zip"
  unzip -o inferenced-linux-amd64.zip && chmod +x inferenced
fi

echo -e "${GREEN}HOT Wallet Option (gonka-account-key):${NC}"
echo "1. Create New HOT Wallet"
echo "2. Import Existing HOT Wallet (Mnemonic)"
read -p "Selection (1/2): " hot_choice

if [ "$hot_choice" == "2" ]; then
    echo -e "${YELLOW}Import HOT wallet (paste mnemonic di prompt CLI)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file --recover)
else
    echo -e "${YELLOW}Membuat HOT wallet baru gonka-account-key (ikuti prompt password & simpan mnemonic)...${NC}"
    WALLET_DATA=$(./inferenced keys add gonka-account-key --keyring-backend file)
fi

echo "$WALLET_DATA"

# Extract Address & PubKey dari HOT wallet
ACCOUNT_ADDRESS=$(echo "$WALLET_DATA" | grep -oP 'gonka1[a-z0-9]+' | head -n 1)
ACCOUNT_PUBKEY=$(echo "$WALLET_DATA" | grep -oP '"key":"\K[^"]+' | head -n 1)

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$ACCOUNT_PUBKEY" ]; then
  echo -e "${RED}Gagal parsing ACCOUNT_ADDRESS atau ACCOUNT_PUBKEY dari output HOT wallet.${NC}"
  exit 1
fi

echo -e "${GREEN}Main Wallet Address (HOT):${NC} $ACCOUNT_ADDRESS"
echo -e "${GREEN}Account PubKey (HOT, from step 2):${NC} $ACCOUNT_PUBKEY"

export ACCOUNT_ADDRESS
export ACCOUNT_PUBKEY

# 2b. Set KEYRING_PASSWORD untuk ml-ops-key
echo
echo -e "${YELLOW}[2b] Set KEYRING_PASSWORD untuk ML Ops (COLD wallet / ml-ops-key)...${NC}"
echo -e "${GREEN}CATAT: Password ini harus sama dengan yang kamu isi saat diminta passphrase di dalam container api.${NC}"
read -s -p "Set KEYRING_PASSWORD (untuk ml-ops-key, jangan pakai spasi): " KEYRING_PASSWORD
echo

echo -e "${GREEN}COLD Wallet Option (ML Ops / ml-ops-key):${NC}"
echo "1. Create New COLD Wallet (ml-ops-key)"
echo "2. Import Existing COLD Wallet (Mnemonic ml-ops-key)"
read -p "Selection (1/2): " cold_choice

# 3. Download Gonka & Prepare Directory
echo -e "${YELLOW}[3/11] Cloning Repository & Preparing Directories...${NC}"
if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Gagal cd ke gonka/deploy/join${NC}"; exit 1; }

cp config.env.template config.env
mkdir -p /mnt/shared

# 4. Modifying config.env
echo -e "${YELLOW}[4/11] Modifying config.env...${NC}"

IPV4=$(curl -4 -s ifconfig.me)

# KEY_NAME fix untuk ML Ops
KEY_NAME="ml-ops-key"

# Set KEY_NAME & KEYRING_PASSWORD
sed -i "s|export KEY_NAME=.*|export KEY_NAME=$KEY_NAME|g" config.env
sed -i "s|export KEYRING_PASSWORD=.*|export KEYRING_PASSWORD=$KEYRING_PASSWORD|g" config.env

# PUBLIC_URL & P2P_EXTERNAL_ADDRESS pakai IP VPS
sed -i "s|export PUBLIC_URL=.*|export PUBLIC_URL=http://$IPV4:8000|g" config.env
sed -i "s|export P2P_EXTERNAL_ADDRESS=.*|export P2P_EXTERNAL_ADDRESS=tcp://$IPV4:5000|g" config.env

# PENTING: ACCOUNT_PUBKEY pakai PUBKEY dari HOT wallet (bukan address)
sed -i "s|export ACCOUNT_PUBKEY=.*|export ACCOUNT_PUBKEY=$ACCOUNT_PUBKEY|g" config.env

# SEED API URL
sed -i "s|export SEED_API_URL=.*|export SEED_API_URL=http://node1.gonka.ai:8000|g" config.env

# Load env
source config.env

# HF_HOME default
[ -z "$HF_HOME" ] && export HF_HOME=/mnt/shared/hf-cache
mkdir -p "$HF_HOME"

# 5. Custom node-config.json
echo -e "${YELLOW}[5/11] Writing custom node-config.json...${NC}"

cat <<'EOF' > node-config.json
[
    {
        "id": "node1",
        "host": "inference",
        "inference_port": 5000,
        "poc_port": 8080,
        "max_concurrent": 250,
        "models": {
            "Qwen/Qwen2.5-7B-Instruct": {
                "args": [
                    "--quantization",
                    "fp8",
                    "--gpu-memory-utilization",
                    "0.9"
                ]
            }
        }
    }
]
EOF

# 6. Install HF CLI & download model weights
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

# 8. Start tmkms + node
echo -e "${YELLOW}[8/11] Starting tmkms and node...${NC}"
source config.env
docker compose up tmkms node -d --no-deps

# 9. COLD WALLET (ml-ops-key) + Register Host
echo -e "${YELLOW}[9/11] Setting up COLD wallet (ml-ops-key) inside api container...${NC}"
echo -e "${GREEN}CATAT: Saat diminta 'Enter keyring passphrase', pakai password yang sama dengan KEYRING_PASSWORD di atas.${NC}"

if [ "$cold_choice" == "2" ]; then
  echo -e "${YELLOW}>> MODE IMPORT COLD WALLET (ml-ops-key) <<${NC}"
  echo -e "${YELLOW}Di dalam container nanti:${NC}"
  echo -e "  - Masukkan keyring passphrase (sama dengan KEYRING_PASSWORD)"
  echo -e "  - Ulangi passphrase"
  echo -e "  - Paste mnemonic ml-ops-key"
  docker compose run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file --recover
else
  echo -e "${YELLOW}>> MODE CREATE COLD WALLET (ml-ops-key) <<${NC}"
  echo -e "${YELLOW}Di dalam container nanti:${NC}"
  echo -e "  - Masukkan keyring passphrase (sama dengan KEYRING_PASSWORD)"
  echo -e "  - Ulangi passphrase"
  echo -e "  - SIMPAN mnemonic ml-ops-key yang muncul!"
  docker compose run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file
fi

# Setelah keluar dari container, ambil address ml-ops-key secara non-interaktif
echo -e "${YELLOW}Mengambil ML Ops address dari keyring di dalam container...${NC}"

ML_OPS_ADDRESS=$(docker compose run --rm --no-deps \
  -e KEY_NAME="$KEY_NAME" -e KEYRING_PASSWORD="$KEYRING_PASSWORD" \
  api /bin/sh -c 'printf "%s\n" "$KEYRING_PASSWORD" | inferenced keys show "$KEY_NAME" --keyring-backend file -a' \
  2>/dev/null | tr -d '\r' | tail -n 1)

if [ -z "$ML_OPS_ADDRESS" ]; then
    echo -e "${RED}Error: Gagal membaca ML Ops address dari ml-ops-key! Pastikan passphrase sama.${NC}"
    exit 1
fi

echo -e "${GREEN}ML Operational Address (COLD / ml-ops-key):${NC} $ML_OPS_ADDRESS"

echo -e "${YELLOW}Registering Host (step 9.1.2) dengan PUBKEY dari HOT wallet (auto retry)...${NC}"

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

# 10. Grant Permissions to ML Operational Key
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

echo -e "${GREEN}=== INSTALLATION FINISHED (HOT & COLD WALLET MODE) ===${NC}"
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
