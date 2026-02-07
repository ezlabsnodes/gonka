#!/bin/bash

# =========================
#  GONKA NETWORK NODE ONE-CLICK
#  VPS TANPA GPU (tmkms + node + api + proxy)
#  HOT ACCOUNT KEY + ML OPS KEY (WARM)
# =========================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

set -e

echo -e "${GREEN}=== GONKA NETWORK NODE AUTO-INSTALLER (SERVER-CPU ONLY) ===${NC}"

# 1. ENVIRONMENT SETUP
echo -e "${YELLOW}[1/11] Menyiapkan environment (unzip, curl, git)...${NC}"
sudo apt update && sudo apt install -y unzip curl git

# Pastikan PATH user
export PATH="$HOME/.local/bin:$PATH"

# 2. DOWNLOAD INFERENCED CLI & SETUP HOT ACCOUNT KEY
echo -e "${YELLOW}[2/11] Download inferenced CLI & setup HOT Account Key...${NC}"

# Simpan binary inferenced di $HOME/inferenced
if [ ! -x "$HOME/inferenced" ]; then
  wget -q -O "$HOME/inferenced-linux-amd64.zip" "https://github.com/gonka-ai/gonka/releases/download/release%2Fv0.2.9/inferenced-linux-amd64.zip"
  unzip -o "$HOME/inferenced-linux-amd64.zip" -d "$HOME" >/dev/null
  chmod +x "$HOME/inferenced"
  rm -f "$HOME/inferenced-linux-amd64.zip"
fi

CLI="$HOME/inferenced"

echo -e "${GREEN}Account Key (HOT di VPS, nama: gonka-account-key):${NC}"
echo "1. Buat Account Key baru"
echo "2. Import Account Key (mnemonic sudah punya)"
read -p "Pilihan (1/2): " hot_choice

if [ "$hot_choice" == "2" ]; then
    echo -e "${YELLOW}Import Account Key (paste mnemonic di prompt CLI)...${NC}"
    WALLET_DATA=$("$CLI" keys add gonka-account-key --keyring-backend file --recover)
else
    echo -e "${YELLOW}Membuat Account Key baru gonka-account-key (ikuti prompt password & simpan mnemonic)...${NC}"
    WALLET_DATA=$("$CLI" keys add gonka-account-key --keyring-backend file)
fi

echo "$WALLET_DATA"

ACCOUNT_ADDRESS=$(echo "$WALLET_DATA" | grep -oP 'gonka1[a-z0-9]+' | head -n 1)
ACCOUNT_PUBKEY=$(echo "$WALLET_DATA" | grep -oP '"key":"\K[^"]+' | head -n 1)

if [ -z "$ACCOUNT_ADDRESS" ] || [ -z "$ACCOUNT_PUBKEY" ]; then
  echo -e "${RED}Gagal parsing ACCOUNT_ADDRESS atau ACCOUNT_PUBKEY dari output Account Key.${NC}"
  exit 1
fi

echo -e "${GREEN}Account Address (HOT / gonka-account-key):${NC} $ACCOUNT_ADDRESS"
echo -e "${GREEN}Account PubKey (HOT / gonka-account-key):${NC} $ACCOUNT_PUBKEY"

export ACCOUNT_ADDRESS
export ACCOUNT_PUBKEY

# 2b. KEYRING_PASSWORD UNTUK ML OPS KEY (WARM KEY)
echo
echo -e "${YELLOW}[2b] Set KEYRING_PASSWORD untuk ML Ops Key (warm key / KEY_NAME di server)...${NC}"
echo -e "${GREEN}CATAT: Password ini DIPAKAI di dalam container api saat generate ML Ops key.${NC}"
read -s -p "Set KEYRING_PASSWORD (jangan pakai spasi): " KEYRING_PASSWORD
echo

KEY_NAME="ml-ops-key"

echo -e "${GREEN}ML Ops Key (warm key / $KEY_NAME):${NC}"
echo "1. Buat ML Ops key baru di server"
echo "2. Import ML Ops key (mnemonic sudah ada)"
read -p "Pilihan (1/2): " cold_choice

# 3. CLONE GONKA & MASUK KE deploy/join
echo -e "${YELLOW}[3/11] Clone repository & siapkan gonka/deploy/join...${NC}"

cd "$HOME"
if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd "$HOME/gonka/deploy/join" || { echo -e "${RED}Gagal cd ke gonka/deploy/join${NC}"; exit 1; }

if [ ! -f "config.env" ]; then
  cp config.env.template config.env
fi

mkdir -p /mnt/shared

# 4. UPDATE config.env (PAKAI node1 SEBAGAI SEED)
echo -e "${YELLOW}[4/11] Update config.env sesuai IP VPS & key...${NC}"

IPV4=$(curl -4 -s ifconfig.me)

# KEY_NAME & KEYRING_PASSWORD (warm key)
sed -i "s|export KEY_NAME=.*|export KEY_NAME=$KEY_NAME|g" config.env
sed -i "s|export KEYRING_PASSWORD=.*|export KEYRING_PASSWORD=$KEYRING_PASSWORD|g" config.env

# PUBLIC URL & P2P
sed -i "s|export PUBLIC_URL=.*|export PUBLIC_URL=http://$IPV4:8000|g" config.env
sed -i "s|export P2P_EXTERNAL_ADDRESS=.*|export P2P_EXTERNAL_ADDRESS=tcp://$IPV4:5000|g" config.env

# ACCOUNT_PUBKEY dari Account Key
sed -i "s|export ACCOUNT_PUBKEY=.*|export ACCOUNT_PUBKEY=$ACCOUNT_PUBKEY|g" config.env

# SEED pakai NODE1
if grep -q "export SEED_API_URL=" config.env; then
  sed -i "s|export SEED_API_URL=.*|export SEED_API_URL=http://node1.gonka.ai:8000|g" config.env
else
  echo "export SEED_API_URL=http://node1.gonka.ai:8000" >> config.env
fi

if grep -q "export SEED_NODE_RPC_URL=" config.env; then
  sed -i "s|export SEED_NODE_RPC_URL=.*|export SEED_NODE_RPC_URL=http://node1.gonka.ai:8000/chain-rpc/|g" config.env
else
  echo "export SEED_NODE_RPC_URL=http://node1.gonka.ai:8000/chain-rpc/" >> config.env
fi

if grep -q "export SEED_NODE_P2P_URL=" config.env; then
  sed -i "s|export SEED_NODE_P2P_URL=.*|export SEED_NODE_P2P_URL=tcp://node1.gonka.ai:5000|g" config.env
else
  echo "export SEED_NODE_P2P_URL=tcp://node1.gonka.ai:5000" >> config.env
fi

# Untuk beberapa config yang pakai DAPI_CHAIN_NODE__SEED_API_URL
if grep -q "export DAPI_CHAIN_NODE__SEED_API_URL=" config.env; then
  sed -i "s|export DAPI_CHAIN_NODE__SEED_API_URL=.*|export DAPI_CHAIN_NODE__SEED_API_URL=http://node1.gonka.ai:8000/chain-rpc/|g" config.env
else
  echo "export DAPI_CHAIN_NODE__SEED_API_URL=http://node1.gonka.ai:8000/chain-rpc/" >> config.env
fi

# CALLBACK untuk PoC dari ML node (GPU server)
if grep -q "export DAPI_API__POC_CALLBACK_URL=" config.env; then
  sed -i "s|export DAPI_API__POC_CALLBACK_URL=.*|export DAPI_API__POC_CALLBACK_URL=http://$IPV4:9100|g" config.env
else
  echo "export DAPI_API__POC_CALLBACK_URL=http://$IPV4:9100" >> config.env
fi

# DAPI_API__PUBLIC_URL (dipakai register-new-participant)
if grep -q "export DAPI_API__PUBLIC_URL=" config.env; then
  sed -i "s|export DAPI_API__PUBLIC_URL=.*|export DAPI_API__PUBLIC_URL=http://$IPV4:8000|g" config.env
else
  echo "export DAPI_API__PUBLIC_URL=http://$IPV4:8000" >> config.env
fi

# OPTIONAL: RPC_SERVER_URL_1/2 → node1
if grep -q "export RPC_SERVER_URL_1=" config.env; then
  sed -i "s|export RPC_SERVER_URL_1=.*|export RPC_SERVER_URL_1=http://node1.gonka.ai:8000/chain-rpc/|g" config.env
fi
if grep -q "export RPC_SERVER_URL_2=" config.env; then
  sed -i "s|export RPC_SERVER_URL_2=.*|export RPC_SERVER_URL_2=http://node1.gonka.ai:8000/chain-rpc/|g" config.env
fi

# HF_HOME kalau belum ada
if ! grep -q "export HF_HOME=" config.env; then
  echo "export HF_HOME=/mnt/shared" >> config.env
fi

# Load env & buat .env untuk docker compose
source config.env
sed 's/^export //' config.env > .env

# 5. node-config.json KOSONG (tidak ada ML node lokal di VPS ini)
echo -e "${YELLOW}[5/11] Menulis node-config.json kosong (tidak ada ML node lokal di VPS ini)...${NC}"

cat > node-config.json << 'EOF'
[]
EOF

# 6. SKIP DOWNLOAD MODEL DI VPS
echo -e "${YELLOW}[6/11] Skip download model (VPS hanya Network Node, ML node di GPU server).${NC}"

# 7. PULL DOCKER IMAGES (NETWORK NODE SAJA)
echo -e "${YELLOW}[7/11] docker compose pull (tmkms + node + api + proxy)...${NC}"
docker compose -f docker-compose.yml pull

# 8. START AWAL: tmkms + node
echo -e "${YELLOW}[8/11] Start awal tmkms + node (tanpa api/proxy, untuk sync chain & consensus key)...${NC}"
docker compose -f docker-compose.yml up tmkms node -d --no-deps

echo -e "${GREEN}tmkms + node berjalan. Kamu bisa cek: cd ~/gonka/deploy/join && docker compose logs tmkms node -f${NC}"

# 9. BUAT / IMPORT ML OPS KEY DI api CONTAINER
echo -e "${YELLOW}[9/11] Setup ML Ops key ($KEY_NAME) di dalam api container...${NC}"
echo -e "${GREEN}Saat diminta 'Enter keyring passphrase', pakai KEYRING_PASSWORD yang kamu set di step 2b.${NC}"

if [ "$cold_choice" == "2" ]; then
  echo -e "${YELLOW}>> IMPORT ML OPS KEY MODE ($KEY_NAME) <<${NC}"
  docker compose -f docker-compose.yml run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file --recover
else
  echo -e "${YELLOW}>> CREATE ML OPS KEY MODE ($KEY_NAME) <<${NC}"
  docker compose -f docker-compose.yml run --rm --no-deps -it api inferenced keys add "$KEY_NAME" --keyring-backend file
fi

# 9a. AMBIL ML OPS ADDRESS
echo -e "${YELLOW}Mengambil ML Ops address dari keyring dalam api container...${NC}"

ML_OPS_ADDRESS=$(
  docker compose -f docker-compose.yml run --rm --no-deps \
    -e KEY_NAME="$KEY_NAME" -e KEYRING_PASSWORD="$KEYRING_PASSWORD" \
    api /bin/sh -c 'printf "%s\n" "$KEYRING_PASSWORD" | inferenced keys show "$KEY_NAME" --keyring-backend file -a' \
    2>/dev/null | tr -d '\r' | tail -n 1
)

if [ -z "$ML_OPS_ADDRESS" ]; then
    echo -e "${RED}Error: Gagal membaca ML Ops address dari $KEY_NAME! Pastikan passphrase benar.${NC}"
    exit 1
fi

echo -e "${GREEN}ML Ops Address (warm key / $KEY_NAME):${NC} $ML_OPS_ADDRESS"

# 9.1 REGISTER HOST (HARDCODE --node-address KE node1.gonka.ai:8000)
echo -e "${YELLOW}[9.1] Register host dengan PUBKEY dari Account Key (auto retry, pakai node1)...${NC}"

REGISTER_OK=0
for i in {1..10}; do
  if env ACCOUNT_PUBKEY="$ACCOUNT_PUBKEY" \
        DAPI_API__PUBLIC_URL="http://$IPV4:8000" \
      docker compose -f docker-compose.yml run --rm --no-deps api /bin/sh -c '
        SEED_NODE_ADDR="http://node1.gonka.ai:8000"
        echo "Node URL (PUBLIC_URL): $DAPI_API__PUBLIC_URL"
        echo "Account Public Key: $ACCOUNT_PUBKEY"
        echo "Seed Node Address: $SEED_NODE_ADDR"
        inferenced register-new-participant \
          "$DAPI_API__PUBLIC_URL" \
          "$ACCOUNT_PUBKEY" \
          --node-address "$SEED_NODE_ADDR"
      '; then
    REGISTER_OK=1
    echo -e "${GREEN}Host registration sukses di attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Host registration gagal (attempt $i), retry 30 detik...${NC}"
    sleep 30
  fi
done

if [ "$REGISTER_OK" -ne 1 ]; then
  echo -e "${RED}Gagal register host setelah banyak percobaan. Cek koneksi ke node1.gonka.ai & ulangi manual.${NC}"
  exit 1
fi

# 10. GRANT PERMISSIONS KE ML OPS KEY (PAKAI node1)
echo -e "${YELLOW}[10/11] Grant ML Ops permissions (auto retry, pakai node1)...${NC}"

cd "$HOME" || { echo -e "${RED}Gagal cd ke \$HOME${NC}"; exit 1; }

GRANT_OK=0
for i in {1..20}; do
  if "$CLI" tx inference grant-ml-ops-permissions \
        gonka-account-key \
        "$ML_OPS_ADDRESS" \
        --from gonka-account-key \
        --keyring-backend file \
        --gas 2000000 \
        --node http://node1.gonka.ai:8000/chain-rpc/ \
        --yes; then
    GRANT_OK=1
    echo -e "${GREEN}Grant ML Ops permissions sukses di attempt $i.${NC}"
    break
  else
    echo -e "${YELLOW}Grant permissions gagal (attempt $i), retry 30 detik...${NC}"
    sleep 30
  fi
done

if [ "$GRANT_OK" -ne 1 ]; then
  echo -e "${RED}Gagal grant ML Ops permissions setelah banyak percobaan.${NC}"
  echo -e "${YELLOW}Node masih bisa jalan, tapi ML Ops key mungkin belum punya permission. Cek manual nanti.${NC}"
fi

# 11. START FULL NETWORK NODE (proxy + api + node + tmkms)
echo -e "${YELLOW}[11/11] Menyalakan semua service NETWORK NODE (proxy + api + node + tmkms)...${NC}"
cd "$HOME/gonka/deploy/join" || { echo -e "${RED}Gagal kembali ke gonka/deploy/join${NC}"; exit 1; }

source config.env
sed 's/^export //' config.env > .env

docker compose -f docker-compose.yml up -d

echo -e "${GREEN}=== NETWORK NODE INSTALLATION FINISHED (NO LOCAL GPU) ===${NC}"
echo -e "Dashboard (via proxy): http://$IPV4:8000/dashboard"

echo
echo -e "${YELLOW}Command log penting:${NC}"
echo "  cd ~/gonka/deploy/join && docker compose -f docker-compose.yml logs --tail 200"
echo
echo "Chain Node:"
echo "  cd ~/gonka/deploy/join && docker logs --tail 500 node"
echo
echo "TMKMS:"
echo "  cd ~/gonka/deploy/join && docker logs --tail 500 tmkms"
echo
echo "API Node:"
echo "  cd ~/gonka/deploy/join && docker logs --tail 500 api"
echo
echo "Proxy:"
echo "  cd ~/gonka/deploy/join && docker logs --tail 500 proxy"
echo
echo -e "${GREEN}Jangan lupa: ML node jalan di server GPU, di-register via Admin API ke http://$IPV4:9100 (poc_callback_url).${NC}"
