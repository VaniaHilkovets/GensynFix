#!/bin/bash
set -e

echo "[*] Cloning BlockAssist..."
cd ~
rm -rf blockassist
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

echo "[*] Running setup.sh (Malmo + Java 1.8.0_152)..."
chmod +x setup.sh
./setup.sh

echo "[*] Installing pyenv..."
curl -fsSL https://pyenv.run | bash

# Добавляем в bashrc
if ! grep -q 'pyenv init' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'EOL'
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOL
fi

# Активируем pyenv в этом сеансе
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "[*] Installing Python 3.10..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev \
libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
pyenv install -s 3.10
pyenv global 3.10

echo "[*] Installing Python packages..."
pip install --upgrade pip
pip install psutil readchar

echo "[*] Starting BlockAssist..."
pyenv exec python run.py
