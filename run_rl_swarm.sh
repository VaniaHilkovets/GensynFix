#!/bin/bash

set -e  # вылетать при ошибке
ROOT=$PWD

export PUB_MULTI_ADDRS
export PEER_MULTI_ADDRS
export HOST_MULTI_ADDRS
export IDENTITY_PATH
export CONNECT_TO_TESTNET
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120  # 2 minutes

# Defaults
DEFAULT_PUB_MULTI_ADDRS=""
DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"
DEFAULT_IDENTITY_PATH="$ROOT/swarm.pem"

# Fallbacks
PUB_MULTI_ADDRS=${PUB_MULTI_ADDRS:-$DEFAULT_PUB_MULTI_ADDRS}
PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

# Prompt
while true; do
    read -p "Would you like to connect to the Testnet? [Y/n] " yn
    yn=${yn:-Y}
    case $yn in
        [Yy]*) CONNECT_TO_TESTNET=True; break;;
        [Nn]*) CONNECT_TO_TESTNET=False; break;;
        *) echo ">>> Please answer yes or no.";;
    esac
done

# Install deps
sudo apt update && sudo apt install -y curl git python3-pip lsof

# Cloudflared
if ! command -v cloudflared >/dev/null 2>&1; then
    echo "Installing Cloudflared..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb
    rm cloudflared-linux-amd64.deb
fi

# Node.js + npm
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

if [ "$CONNECT_TO_TESTNET" = "True" ]; then
    echo "Please login to create an Ethereum Server Wallet"
    cd modal-login

    rm -rf node_modules package-lock.json yarn.lock
    npm install --legacy-peer-deps

    # Fix sonic
    if [ -f node_modules/@account-kit/infra/dist/esm/chains.js ]; then
        sed -i '/import.*sonic/d' node_modules/@account-kit/infra/dist/esm/chains.js || true
    fi

    npm run dev > "$ROOT/server.log" 2>&1 &
    SERVER_PID=$!
    cd "$ROOT"

    echo -e "\nOpen new window and run:"
    echo "cloudflared tunnel --url http://localhost:3000"

    echo "Waiting for userData.json..."
    while [ ! -f modal-login/temp-data/userData.json ]; do
        sleep 3
        echo "Waiting..."
    done

    echo "✓ userData.json found"
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)

    # API activation
    echo "Waiting for API key activation..."
    while true; do
        STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
        if [[ "$STATUS" == "activated" ]]; then
            echo "✓ API key is activated"
            break
        else
            echo "Waiting for activation..."
            sleep 5
        fi
    done

    trap 'kill $SERVER_PID; rm -f modal-login/temp-data/*.json' INT
fi

# Install Python deps
pip install -r "$ROOT/requirements-hivemind.txt" > /dev/null
pip install -r "$ROOT/requirements.txt" > /dev/null

if which nvidia-smi >/dev/null; then
    pip install -r "$ROOT/requirements_gpu.txt" > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

# HuggingFace
if [ -n "$HF_TOKEN" ]; then
    HUGGINGFACE_ACCESS_TOKEN=$HF_TOKEN
else
    read -p "Upload to HuggingFace? [y/N]: " yn
    yn=${yn:-N}
    if [[ $yn =~ ^[Yy]$ ]]; then
        read -p "Enter HF token: " HUGGINGFACE_ACCESS_TOKEN
    else
        HUGGINGFACE_ACCESS_TOKEN="None"
    fi
fi

# Start
echo -e "\n\e[1;35mLaunching node...\e[0m"
if [ -n "$ORG_ID" ]; then
    python3 -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --config "$CONFIG_PATH"
else
    python3 -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH"
fi

wait
