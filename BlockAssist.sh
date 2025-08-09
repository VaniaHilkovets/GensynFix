#!/bin/bash
# BlockAssist Official Installation Script
set -e

echo "========================================="
echo "BlockAssist Official Installer"
echo "========================================="

# Step 1: Clone the repo and enter the directory
echo -e "\n[Step 1] Cloning repository..."
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Step 2: Install Java 1.8.0_152
echo -e "\n[Step 2] Installing Java..."
chmod +x setup.sh
./setup.sh

# Step 3: Install pyenv
echo -e "\n[Step 3] Installing pyenv..."
curl -fsSL https://pyenv.run | bash

# Add pyenv to bashrc
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc

# Load pyenv for current session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Step 4: Install Python 3.10
echo -e "\n[Step 4] Installing Python 3.10..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
pyenv install 3.10
pyenv local 3.10

# Step 5: Install psutil and readchar
echo -e "\n[Step 5] Installing Python packages..."
pip install psutil readchar

echo -e "\n========================================="
echo "Installation complete!"
echo "To run BlockAssist: python run.py"
echo "========================================="
