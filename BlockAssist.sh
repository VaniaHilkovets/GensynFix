#!/bin/bash
# BlockAssist Official Installer
set -e

echo "========================================="
echo "BlockAssist Installer"
echo "========================================="

# Установка Firefox и создание ярлыка
echo -e "\n[0/5] Установка Firefox..."
sudo apt update
sudo apt install -y firefox

# Создание ярлыка Firefox на рабочем столе
DESKTOP_DIR="$HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ]; then
    DESKTOP_DIR="$HOME/Рабочий стол"
fi
if [ ! -d "$DESKTOP_DIR" ]; then
    mkdir -p "$DESKTOP_DIR"
fi

cat > "$DESKTOP_DIR/Firefox.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=Firefox Web Browser
Exec=firefox %u
Terminal=false
Type=Application
Icon=firefox
Categories=Network;WebBrowser;
EOF
chmod +x "$DESKTOP_DIR/Firefox.desktop"

# Step 1: Clone repo
echo -e "\n[1/5] Clone the repo and enter the directory..."
cd ~
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Step 2: Install Java
echo -e "\n[2/5] Install Java 1.8.0_152..."
./setup.sh

# Step 3: Install pyenv
echo -e "\n[3/5] Install pyenv..."
curl -fsSL https://pyenv.run | bash

# Добавляем pyenv в bashrc
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc

# Активируем pyenv для текущей сессии
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Step 4: Install Python 3.10
echo -e "\n[4/5] Install Python 3.10..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
pyenv install 3.10
pyenv global 3.10

# Активируем Python 3.10
eval "$(pyenv init -)"

# Step 5: Install psutil and readchar
echo -e "\n[5/5] Install psutil and readchar..."
pip install psutil readchar

echo -e "\n========================================="
echo "Установка завершена!"
echo ""
echo "Теперь вы можете запустить BlockAssist:"
echo "  cd ~/blockassist && python run.py"
echo ""
echo "Firefox установлен и ярлык создан на рабочем столе"
echo "========================================="
