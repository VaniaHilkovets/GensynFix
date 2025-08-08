#!/bin/bash
set -e

echo "[*] Adding TurboVNC & VirtualGL GPG keys..."
curl -fsSL https://packagecloud.io/dcommander/turbovnc/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/turbovnc.gpg
curl -fsSL https://packagecloud.io/dcommander/virtualgl/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/virtualgl.gpg

echo "[*] Adding repos..."
echo "deb [signed-by=/usr/share/keyrings/turbovnc.gpg] https://packagecloud.io/dcommander/turbovnc/any any main" | sudo tee /etc/apt/sources.list.d/turbovnc.list
echo "deb [signed-by=/usr/share/keyrings/virtualgl.gpg] https://packagecloud.io/dcommander/virtualgl/any any main" | sudo tee /etc/apt/sources.list.d/virtualgl.list

sudo apt update

echo "[*] Installing dependencies..."
sudo apt install -y virtualgl turbovnc libegl1-mesa make build-essential libssl-dev \
zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev \
xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev python3-pip

echo "[*] Cloning BlockAssist..."
cd ~
rm -rf blockassist
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

echo "[*] Running setup.sh (Java + Malmo)..."
chmod +x setup.sh
./setup.sh

echo "[*] Installing pyenv..."
curl -fsSL https://pyenv.run | bash

if ! grep -q 'pyenv init' ~/.bashrc; then
  cat >> ~/.bashrc <<'EOL'
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOL
fi

export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "[*] Installing Python 3.10..."
pyenv install -s 3.10
pyenv global 3.10

echo "[*] Installing Python packages..."
pip install --upgrade pip
pip install psutil readchar

echo "[*] Starting BlockAssist..."
pyenv exec python run.py
