#!/bin/bash
set -e

# =========================
#  GONKA ML NODE ONE-CLICK 
#  SERVER-GPU
# =========================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA ML NODE AUTO-INSTALLER (SERVER-GPU) ===${NC}"

# =========================
# 0. PRE-FLIGHT & DEPENDENCIES
# =========================

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Jalankan script ini sebagai root (sudo su)${NC}"
  exit 1
fi

echo -e "${YELLOW}[0/6] Menginstall dependencies...${NC}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y git pipx iptables-persistent

# Pastikan PATH pipx terdaftar
pipx ensurepath --force > /dev/null 2>&1
export PATH="$HOME/.local/bin:$PATH"

echo "----------------------------------------------------"
read -p "Masukkan IP Address Chain Node (CPU): " CHAIN_NODE_IP
echo "----------------------------------------------------"

if [[ -z "$CHAIN_NODE_IP" ]]; then
  echo -e "${RED}Error: IP tidak boleh kosong!${NC}"
  exit 1
fi

# =========================
# 1. PREPARE DIRECTORIES
# =========================
echo -e "${YELLOW}[1/6] Cloning repository...${NC}"

if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Gagal masuk folder${NC}"; exit 1; }
mkdir -p /mnt/shared

# =========================
# 2. MODIFY CONFIG
# =========================
echo -e "${YELLOW}[2/6] Menulis config.env...${NC}"

cat > config.env << EOF
export HF_HOME=/mnt/shared
export PORT=8080
export INFERENCE_PORT=5050
EOF

source config.env
mkdir -p "$HF_HOME"

# =========================
# 3. CONFIGURE HF CLI (DETECTION FIX)
# =========================
echo -e "${YELLOW}[3/6] Setting up Hugging Face CLI...${NC}"

if ! command -v huggingface-cli &> /dev/null && ! command -v hf &> /dev/null; then
    pipx install "huggingface_hub[cli]" --force
fi

# Deteksi perintah mana yang aktif (hf atau huggingface-cli)
if command -v huggingface-cli &> /dev/null; then
    HF_CMD="huggingface-cli"
elif command -v hf &> /dev/null; then
    HF_CMD="hf"
else
    echo -e "${RED}Error: CLI tetap tidak ditemukan setelah instalasi.${NC}"
    exit 1
fi

# =========================
# MODEL SELECTION
# =========================
echo -e "\n${YELLOW}Pilih model untuk didownload:${NC}"
echo "  1) Qwen/Qwen2.5-7B-Instruct"
echo "  2) Qwen/Qwen3-32B-FP8"
read -p "Pilihan [1-2]: " MODEL_CHOICE

case "$MODEL_CHOICE" in
  1) MODEL_ID="Qwen/Qwen2.5-7B-Instruct" ;;
  2) MODEL_ID="Qwen/Qwen3-32B-FP8" ;;
  *) echo -e "${RED}Pilihan tidak valid.${NC}"; exit 1 ;;
esac

echo -e "${GREEN}Mendownload $MODEL_ID menggunakan $HF_CMD...${NC}"
$HF_CMD download "$MODEL_ID" --cache-dir "$HF_HOME"

# =========================
# 4. DOCKER OPERATIONS
# =========================
echo -e "${YELLOW}[4/6] Pulling Docker images...${NC}"
docker compose -f docker-compose.mlnode.yml pull

echo -e "${YELLOW}[5/6] Memulai ML Node...${NC}"
docker compose -f docker-compose.mlnode.yml up -d

# =========================
# 6. SECURITY LOCK (IPTABLES)
# =========================
echo -e "${YELLOW}[6/6] Mengamankan Port 8080 (Whitelist: $CHAIN_NODE_IP)...${NC}"

EXT_IF=$(ip route get 8.8.8.8 | awk -- '{print $5}')

# Bersihkan aturan lama
iptables -D DOCKER-USER -i "$EXT_IF" -p tcp --dport 8080 -j DROP 2>/dev/null || true
iptables -D DOCKER-USER -i "$EXT_IF" -s "$CHAIN_NODE_IP" -p tcp --dport 8080 -j RETURN 2>/dev/null || true

# Terapkan aturan baru
iptables -I DOCKER-USER 1 -i "$EXT_IF" -s "$CHAIN_NODE_IP" -p tcp --dport 8080 -j RETURN
iptables -I DOCKER-USER 2 -i "$EXT_IF" -p tcp --dport 8080 -j DROP

# Simpan permanen
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
fi

echo -e "\n${GREEN}=== ML NODE BERHASIL DIJALANKAN & AMAN ===${NC}"
echo -e "Hanya IP ${CHAIN_NODE_IP} yang bisa mengakses port 8080."
