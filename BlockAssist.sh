#!/bin/bash
# BlockAssist Simple Installer Script
set -e

echo "========================================="
echo "BlockAssist Installer"
echo "========================================="

# Крок 1: Системні залежності та браузер
echo -e "\n[1/5] Встановлення системних залежностей та браузера..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
   libbz2-dev libreadline-dev libsqlite3-dev curl git \
   libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
   libffi-dev liblzma-dev chromium-browser

# Крок 2: Клонування і запуск setup.sh
echo -e "\n[2/5] Клонування репозиторію..."
cd ~
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist
PROJECT_DIR=$(pwd)

echo -e "\n[3/5] Запуск офіційного скрипта установки..."
chmod +x setup.sh
./setup.sh

# Крок 4: Встановлення pyenv і Python
echo -e "\n[4/5] Встановлення Python через pyenv..."
if ! command -v pyenv &> /dev/null; then
   curl -fsSL https://pyenv.run | bash
   echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
   echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
   echo 'eval "$(pyenv init -)"' >> ~/.bashrc
   
   export PYENV_ROOT="$HOME/.pyenv"
   export PATH="$PYENV_ROOT/bin:$PATH"
   eval "$(pyenv init -)"
fi

pyenv install 3.10
pyenv local 3.10
pip install psutil readchar

# Крок 5: Створення ярлика на робочому столі
echo -e "\n[5/5] Створення ярлика на робочому столі..."
DESKTOP_DIR="$HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ]; then
   DESKTOP_DIR="$HOME/Рабочий стол"
fi
if [ ! -d "$DESKTOP_DIR" ]; then
   mkdir -p "$DESKTOP_DIR"
fi

cat > "$DESKTOP_DIR/BlockAssist.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=BlockAssist
Comment=Run BlockAssist
Icon=$PROJECT_DIR/splash.png
Exec=gnome-terminal --working-directory=$PROJECT_DIR -- bash -c "pyenv local 3.10 && python run.py; read -p 'Press Enter to close...'"
Terminal=false
Categories=Application;Development;
EOF

# Робимо ярлик виконуваним
chmod +x "$DESKTOP_DIR/BlockAssist.desktop"

# Якщо це Ubuntu з GNOME, дозволяємо запуск
if command -v gio &> /dev/null; then
   gio set "$DESKTOP_DIR/BlockAssist.desktop" metadata::trusted true
fi

echo -e "\n========================================="
echo "Установка завершена!"
echo ""
echo "✅ Встановлено:"
echo "  - Chromium Browser"
echo "  - BlockAssist та всі залежності"
echo "  - Ярлик на робочому столі"
echo ""
echo "Для запуску:"
echo "  - Двічі клікніть на ярлик BlockAssist на робочому столі"
echo "  - Або виконайте: cd $PROJECT_DIR && python run.py"
echo "========================================="
