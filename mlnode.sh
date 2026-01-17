#!/bin/bash

# =========================
#  GONKA ML NODE ONE-CLICK
#  SERVER-GPU (ML NODE ONLY)
# =========================

# Output Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== GONKA ML NODE AUTO-INSTALLER (SERVER-GPU) ===${NC}"

# 1. Download Gonka & Prepare HF Cache Dir
echo -e "${YELLOW}[1/5] Cloning repository & preparing directories...${NC}"

if [ ! -d "gonka" ]; then
  git clone https://github.com/gonka-ai/gonka.git -b main
fi

cd gonka/deploy/join || { echo -e "${RED}Failed to cd into gonka/deploy/join${NC}"; exit 1; }

cp config.env.template config.env 2>/dev/null || touch config.env
mkdir -p /mnt/shared

# 2. Modifying Config (ML node only)
echo -e "${YELLOW}[2/5] Writing config.env for ML node only...${NC}"

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

# 3. Install HF CLI
echo -e "${YELLOW}[3/5] Installing Hugging Face CLI...${NC}"

sudo apt update && sudo apt install -y pipx
pipx install --force "huggingface_hub[cli]"
pipx ensurepath
export PATH="$HOME/.local/bin:$PATH"

HF_CMD=$(command -v hf || command -v huggingface-cli || echo "")
if [ -z "$HF_CMD" ]; then
    echo -e "${RED}Error: Hugging Face CLI not found.${NC}"
    exit 1
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
echo -e "${YELLOW}[4/5] Pulling Docker images for ML node...${NC}"
docker compose -f docker-compose.mlnode.yml pull

# 5. Start ML Node
echo -e "${YELLOW}[5/5] Starting ML node...${NC}"
source config.env
docker compose -f docker-compose.mlnode.yml up -d

echo
echo -e "${GREEN}=== ML NODE STARTED (SERVER-GPU) ===${NC}"
echo -e "${YELLOW}Check containers:${NC}"
echo "  cd ~/gonka/deploy/join"
echo "  docker compose -f docker-compose.mlnode.yml ps"
echo
echo -e "${YELLOW}Check logs:${NC}"
echo "  docker logs --tail 200 <mlnode-container-name>"
