#!/bin/bash

# BlockAssist Ubuntu Installer Script
# Цей скрипт автоматично встановлює всі залежності для BlockAssist

set -e  # Вийти при помилці

echo "========================================="
echo "BlockAssist Installer для Ubuntu"
echo "========================================="

# Крок 1: Клонування репозиторію
echo -e "\n[1/5] Клонування репозиторію BlockAssist..."
if [ -d "blockassist" ]; then
    echo "Директорія blockassist вже існує. Видаляю..."
    rm -rf blockassist
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Крок 2: Встановлення Java
echo -e "\n[2/5] Встановлення Java 1.8.0_152..."
chmod +x setup.sh
./setup.sh

# Крок 3: Встановлення pyenv
echo -e "\n[3/5] Встановлення pyenv..."
if command -v pyenv &> /dev/null; then
    echo "pyenv вже встановлено"
else
    curl -fsSL https://pyenv.run | bash
    
    # Додавання pyenv до bashrc
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    
    # Завантаження змін
    export PYENV_ROOT="$HOME/.pyenv"
    command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi

# Крок 4: Встановлення залежностей для Python
echo -e "\n[4/5] Встановлення залежностей для збірки Python..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev curl git \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev

# Встановлення Python 3.10
echo -e "\n[4/5] Встановлення Python 3.10..."
if pyenv versions | grep -q "3.10"; then
    echo "Python 3.10 вже встановлено"
else
    pyenv install 3.10
fi

# Встановлення Python 3.10 як локальну версію для цього проекту
pyenv local 3.10

# Крок 5: Встановлення Python пакетів
echo -e "\n[5/5] Встановлення psutil та readchar..."
pyenv exec pip install --upgrade pip
pyenv exec pip install psutil readchar

echo -e "\n========================================="
echo "Встановлення завершено!"
echo "========================================="
echo ""
echo "Для запуску BlockAssist використовуйте:"
echo "  cd $(pwd)"
echo "  python run.py"
echo ""
echo "Для моніторингу логів:"
echo "  ls logs"
echo "  tail -f logs/<name>.log"
echo ""
echo "ВАЖЛИВО: Перезапустіть термінал або виконайте:"
echo "  source ~/.bashrc"
echo ""
