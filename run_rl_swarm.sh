#!/bin/bash

set -e  # вылетать при ошибке
ROOT=$PWD

export HF_HUB_DOWNLOAD_TIMEOUT=120
DEFAULT_IDENTITY_PATH="$ROOT/swarm.pem"
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DEFAULT_PEER_MULTI_ADDRS="/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ"
DEFAULT_HOST_MULTI_ADDRS="/ip4/0.0.0.0/tcp/38331"

PEER_MULTI_ADDRS=${PEER_MULTI_ADDRS:-$DEFAULT_PEER_MULTI_ADDRS}
HOST_MULTI_ADDRS=${HOST_MULTI_ADDRS:-$DEFAULT_HOST_MULTI_ADDRS}

# Устанавливаем python и pip, если нет
echo -e "\n\e[1;33m[0/4] Проверка Python и pip...\e[0m"
sudo apt update
sudo apt install -y python3 python3-pip
sudo ln -s $(which python3) /usr/bin/python || true

# Спрашиваем про подключение к Testnet
read -p $'\e[1;36mПодключиться к Testnet? [Y/n]: \e[0m' yn
yn=${yn:-Y}
if [[ $yn =~ ^[Yy]$ ]]; then
    CONNECT_TO_TESTNET=True
else
    CONNECT_TO_TESTNET=False
fi

if [[ "$CONNECT_TO_TESTNET" == "True" ]]; then
    echo -e "\n\e[1;33m[1/4] Устанавливаем Node.js 20 и npm (если не установлены)...\e[0m"
    if ! command -v node >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    echo -e "\n\e[1;33m[2/4] Устанавливаем зависимости...\e[0m"
    cd "$ROOT/modal-login"

    rm -rf node_modules package-lock.json yarn.lock

    npm install --legacy-peer-deps

    echo -e "\n\e[1;33m[3/4] Патчим проблему с sonic...\e[0m"
    sed -i '/import.*sonic/d' node_modules/@account-kit/react/node_modules/@account-kit/infra/dist/esm/chains.js || true

    echo -e "\n\e[1;33m[4/4] Запускаем dev сервер...\e[0m"
    npm run dev > "$ROOT/server.log" 2>&1 &
    SERVER_PID=$!
    cd "$ROOT"

    echo -e "\n\e[1;36mОткрой новое окно и выполни:\e[0m"
    echo -e "\e[1;32mcloudflared tunnel --url http://localhost:3000\e[0m"

    echo -e "\nОжидаем появления userData.json..."
    while [ ! -f "modal-login/temp-data/userData.json" ]; do
        sleep 3
        echo "Waiting..."
    done

    echo -e "\n\e[1;32m✓ userData.json найден\e[0m"
    ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' modal-login/temp-data/userData.json)
fi

# Ставим питон зависимости
pip install -r "$ROOT/requirements-hivemind.txt" > /dev/null
pip install -r "$ROOT/requirements.txt" > /dev/null

if which nvidia-smi >/dev/null; then
    pip install -r "$ROOT/requirements_gpu.txt" > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

# Хаб токен
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

# Запуск
echo -e "\n\e[1;35mЗапуск ноды...\e[0m"
if [ -n "$ORG_ID" ]; then
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --modal_org_id "$ORG_ID" \
        --config "$CONFIG_PATH"
else
    python -m hivemind_exp.gsm8k.train_single_gpu \
        --hf_token "$HUGGINGFACE_ACCESS_TOKEN" \
        --identity_path "$IDENTITY_PATH" \
        --public_maddr "$PUB_MULTI_ADDRS" \
        --initial_peers "$PEER_MULTI_ADDRS" \
        --host_maddr "$HOST_MULTI_ADDRS" \
        --config "$CONFIG_PATH"
fi
