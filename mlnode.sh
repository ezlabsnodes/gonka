#!/bin/bash
set -e

# =========================
#  GONKA ML NODE ONE-CLICK
#  SERVER-GPU (ML NODE ONLY + SECURITY LOCK)
# =========================

# Output Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA ML NODE AUTO-INSTALLER (SERVER-GPU) ===${NC}"

# =========================
# 0. SECURITY INPUT
# =========================
echo "----------------------------------------------------"
echo "Enter the IP Address of your Chain Node (CPU)."
echo "Only this IP will be allowed to access the GPU."
echo "----------------------------------------------------"
read -p "Chain Node IP: " CHAIN_NODE_IP

if [[ -z "$CHAIN_NODE_IP" ]]; then
  echo -e "${RED}Error: IP cannot be empty!${NC}"
  exit 1
fi

# 1. Download Gonka & Prepare HF Cache Dir
echo -e "${YELLOW}[1/6] Cloning repository & preparing directories...${NC}"

if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Failed to cd into gonka/deploy/join${NC}"; exit 1; }

cp config.env.template config.env 2>/dev/null || touch config.env
mkdir -p /mnt/shared

# 2. Modifying Config (ML node only)
echo -e "${YELLOW}[2/6] Writing config.env for ML node only...${NC}"

cat > config.env << 'EOF'
export HF_HOME=/mnt/shared
export PORT=8080
export INFERENCE_PORT=5050
EOF

source config.env
export HF_HOME PORT INFERENCE_PORT

echo -e "${GREEN}HF_HOME set to:${NC} $HF_HOME"
echo -e "${GREEN}ML Node Port:${NC} $PORT"
echo -e "${GREEN}Inference Port:${NC} $INFERENCE_PORT"

mkdir -p "$HF_HOME"

# 3. Configure HF CLI
echo -e "${YELLOW}[3/6] Configuring Hugging Face CLI...${NC}"

# Ensure path is correct without reinstalling dependencies
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

HF_CMD=$(command -v hf || command -v huggingface-cli || echo "")
if [ -z "$HF_CMD" ]; then
    echo -e "${YELLOW}HF CLI not found in path. Attempting to force link via pipx...${NC}"
    pipx install --force "huggingface_hub[cli]"
    HF_CMD=$(command -v hf || command -v huggingface-cli || echo "")
fi

# =========================
# MODEL SELECTION
# =========================
echo
echo -e "${YELLOW}Select model to download:${NC}"
echo "  1) Qwen/Qwen2.5-7B-Instruct"
echo "  2) Qwen/Qwen3-32B-FP8"
echo

read -p "Enter choice [1-2]: " MODEL_CHOICE

case "$MODEL_CHOICE" in
  1)
    MODEL_ID="Qwen/Qwen2.5-7B-Instruct"
    ;;
  2)
    MODEL_ID="Qwen/Qwen3-32B-FP8"
    ;;
  *)
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}Selected model:${NC} $MODEL_ID"
echo -e "${YELLOW}Downloading model (HF_HOME=$HF_HOME)...${NC}"

"$HF_CMD" download "$MODEL_ID"

# 4. Pull Containers (ML node only)
echo -e "${YELLOW}[4/6] Pulling Docker images for ML node...${NC}"
docker compose -f docker-compose.mlnode.yml pull

# 5. Start ML Node
echo -e "${YELLOW}[5/6] Starting ML node...${NC}"
source config.env
docker compose -f docker-compose.mlnode.yml up -d

# =========================
# 6. SECURITY LOCK (IPTABLES FIX)
# =========================
echo -e "${YELLOW}[6/6] Applying Security Rules (Locking to IP: $CHAIN_NODE_IP)...${NC}"

# Auto-detect internet interface (e.g., eth0, ens3)
EXT_IF=$(ip route get 8.8.8.8 | awk -- '{print $5}')
echo -e "${GREEN}Detected Interface: ${EXT_IF}${NC}"

# Clean up old rules in DOCKER-USER chain regarding port 8080 to avoid duplicates
iptables -S DOCKER-USER | grep "8080" | sed 's/-A/-D/' | while read rule; do iptables $rule; done || true

# --- APPLY NEW RULES (ANTI-DOCKER BYPASS) ---

# 1. ALLOW (RETURN) if source IP is your Chain Node
iptables -I DOCKER-USER 1 -i "$EXT_IF" -s "$CHAIN_NODE_IP" -p tcp --dport 8080 -j RETURN

# 2. BLOCK (DROP) everyone else trying to access port 8080
iptables -I DOCKER-USER 2 -i "$EXT_IF" -p tcp --dport 8080 -j DROP

# Try to save permanently if netfilter-persistent is available
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
    echo -e "${GREEN}Rules saved permanently.${NC}"
else
    echo -e "${YELLOW}Warning: netfilter-persistent not found. Rules might reset after reboot.${NC}"
fi

echo
echo -e "${GREEN}=== ML NODE STARTED & SECURED ===${NC}"
echo -e "${GREEN}Only IP ${CHAIN_NODE_IP} is allowed to access port 8080.${NC}"
echo -e "${YELLOW}Check containers:${NC}"
echo "  cd ~/gonka/deploy/join"
echo "  docker compose -f docker-compose.mlnode.yml ps"
