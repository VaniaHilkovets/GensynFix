#!/bin/bash
set -e

echo "[*] Installing dependencies..."
sudo apt update -y
sudo apt install -y openjdk-8-jdk make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev \
    xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    python3-pip python3-venv

echo "[*] Cloning BlockAssist..."
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

echo "[*] Running setup.sh..."
chmod +x setup.sh
./setup.sh

echo "[*] Installing pyenv..."
curl -fsSL https://pyenv.run | bash

# Добавляем pyenv в окружение текущей сессии
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "[*] Installing Python 3.10..."
pyenv install 3.10
pyenv global 3.10

echo "[*] Installing Python packages..."
pip install --upgrade pip
pip install psutil readchar

echo "[*] Starting BlockAssist..."
source blockassist-venv/bin/activate
vglrun python run.py
