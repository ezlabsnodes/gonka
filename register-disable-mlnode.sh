#!/bin/bash

# ==============================
#  GONKA ADMIN ML NODE HELPER
#  (Register / Enable / Disable)
#  Run on SERVER-CPU (Chain Node)
# ==============================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

API_BASE="http://localhost:9200/admin/v1/nodes"

echo -e "${GREEN}=== GONKA REGISTER/DISABLE ML NODE ===${NC}"
echo "1. Register & Enable ML Node"
echo "2. Disable ML Node"
echo
read -p "Select (1/2): " MAIN_CHOICE

if [ "$MAIN_CHOICE" == "1" ]; then
  echo
  echo -e "${YELLOW}== Register & Enable ML Node ==${NC}"
  read -p "Enter ML Node ID/Name (e.g. node1): " NODE_ID
  read -p "Enter GPU SERVER VPS IP (e.g. 1.2.3.4): " GPU_HOST

  if [ -z "$NODE_ID" ] || [ -z "$GPU_HOST" ]; then
    echo -e "${RED}Node ID and GPU SERVER IP must not be empty.${NC}"
    exit 1
  fi

  echo
  echo -e "${GREEN}Select ML Node Profile:${NC}"
  echo "1. Qwen/Qwen3-235B-A22B-Instruct-2507-FP8"
  echo "2. Qwen/Qwen3-235B-A22B-Instruct-2507-FP8"
  echo
  read -p "Select (1/2): " MODEL_CHOICE

  echo

  case "$MODEL_CHOICE" in
    1)
      echo -e "${YELLOW}Registering ML Node: 1x L40S (Qwen/Qwen3-32B-FP8)...${NC}"
      JSON_BODY=$(cat <<EOF
{
  "id": "$NODE_ID",
  "host": "$GPU_HOST",
  "inference_port": 5050,
  "poc_port": 8080,
  "max_concurrent": 500,

  "models": {
    "Qwen/Qwen3-235B-A22B-Instruct-2507-FP8": {
      "args": [
        "--tensor-parallel-size", "4"
      ]
    }
  }
}
EOF
)
      ;;

    2)
      echo -e "${YELLOW}Registering ML Node: 2x L40S (Qwen/Qwen3-32B-FP8)...${NC}"
      JSON_BODY=$(cat <<EOF
{
  "id": "$NODE_ID",
  "host": "$GPU_HOST",
  "inference_port": 5050,
  "poc_port": 8080,
  "max_concurrent": 200,
  "models": {
    "Qwen/Qwen3-235B-A22B-Instruct-2507-FP8": {
      "args": [
        "--tensor-parallel-size", "4"
      ]
    }
  }
}
EOF
)
      ;;

    *)
      echo -e "${RED}Invalid model selection.${NC}"
      exit 1
      ;;
  esac

  echo -e "${YELLOW}Sending register request to ${API_BASE}...${NC}"
  echo -e "${YELLOW}Payload:${NC}"
  echo "$JSON_BODY"
  echo

  RESP_REGISTER=$(curl -sS -o /tmp/gonka_register_resp.json -w "%{http_code}" \
    -X POST "$API_BASE" \
    -H "Content-Type: application/json" \
    -d "$JSON_BODY")

  if [ "$RESP_REGISTER" -ge 200 ] && [ "$RESP_REGISTER" -lt 300 ]; then
    echo -e "${GREEN}ML node registration succeeded (HTTP $RESP_REGISTER).${NC}"
  else
    echo -e "${RED}ML node registration failed (HTTP $RESP_REGISTER). See /tmp/gonka_register_resp.json for details.${NC}"
    cat /tmp/gonka_register_resp.json
    echo
    exit 1
  fi

  echo
  echo -e "${YELLOW}Enabling ML Node: $NODE_ID ...${NC}"
  RESP_ENABLE=$(curl -sS -o /tmp/gonka_enable_resp.json -w "%{http_code}" \
    -X POST "$API_BASE/$NODE_ID/enable")

  if [ "$RESP_ENABLE" -ge 200 ] && [ "$RESP_ENABLE" -lt 300 ]; then
    echo -e "${GREEN}ML node $NODE_ID successfully enabled (HTTP $RESP_ENABLE).${NC}"
  else
    echo -e "${RED}Enabling ML node failed (HTTP $RESP_ENABLE). See /tmp/gonka_enable_resp.json for details.${NC}"
    cat /tmp/gonka_enable_resp.json
    echo
    exit 1
  fi

  echo
  echo -e "${YELLOW}Verifying node status (id & status):${NC}"
  if command -v jq >/dev/null 2>&1; then
    curl -sS "$API_BASE" | jq '.[] | {id: .node.id, status: .state.current_status}'
  else
    echo -e "${YELLOW}jq not found, printing raw JSON:${NC}"
    curl -sS "$API_BASE"
  fi
  echo

elif [ "$MAIN_CHOICE" == "2" ]; then
  echo
  echo -e "${YELLOW}== Disable ML Node ==${NC}"
  read -p "Enter ML Node ID/Name to disable: " NODE_ID

  if [ -z "$NODE_ID" ]; then
    echo -e "${RED}Node ID must not be empty.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}Disabling ML Node: $NODE_ID ...${NC}"
  RESP_DISABLE=$(curl -sS -o /tmp/gonka_disable_resp.json -w "%{http_code}" \
    -X POST "$API_BASE/$NODE_ID/disable")

  if [ "$RESP_DISABLE" -ge 200 ] && [ "$RESP_DISABLE" -lt 300 ]; then
    echo -e "${GREEN}ML node $NODE_ID successfully disabled (HTTP $RESP_DISABLE).${NC}"
  else
    echo -e "${RED}Disabling ML node failed (HTTP $RESP_DISABLE). See /tmp/gonka_disable_resp.json for details.${NC}"
    cat /tmp/gonka_disable_resp.json
    echo
    exit 1
  fi

  echo
  echo -e "${YELLOW}Verifying node status (id & status):${NC}"
  if command -v jq >/dev/null 2>&1; then
    curl -sS "$API_BASE" | jq '.[] | {id: .node.id, status: .state.current_status}'
  else
    echo -e "${YELLOW}jq not found, printing raw JSON:${NC}"
    curl -sS "$API_BASE"
  fi
  echo

else
  echo -e "${RED}Unknown option. Exit.${NC}"
  exit 1
fi
