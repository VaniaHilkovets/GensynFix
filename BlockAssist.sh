#!/bin/bash
# BlockAssist Ubuntu Installer Script
# Цей скрипт автоматично встановлює всі залежності для BlockAssist
set -e  # Вийти при помилці

echo "========================================="
echo "BlockAssist Installer для Ubuntu"
echo "========================================="

# Крок 1: Встановлення всіх системних залежностей
echo -e "\n[1/6] Встановлення системних залежностей..."
sudo apt update
sudo apt install -y make build-essential gcc \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    curl git

# Крок 2: Клонування репозиторію
echo -e "\n[2/6] Клонування репозиторію BlockAssist..."
if [ -d "blockassist" ]; then
    echo "Директорія blockassist вже існує. Видаляю..."
    rm -rf blockassist
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Крок 3: Встановлення Java
echo -e "\n[3/6] Встановлення Java 1.8.0_152..."
chmod +x setup.sh
./setup.sh

# Крок 4: Встановлення pyenv
echo -e "\n[4/6] Встановлення pyenv..."
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

# Крок 5: Встановлення Python 3.10
echo -e "\n[5/6] Встановлення Python 3.10..."
if pyenv versions | grep -q "3.10"; then
    echo "Python 3.10 вже встановлено"
else
    pyenv install 3.10
fi

# Встановлення Python 3.10 як локальну версію для цього проекту
pyenv local 3.10

# Крок 6: Встановлення Python пакетів
echo -e "\n[6/6] Встановлення Python пакетів..."
pyenv exec pip install --upgrade pip
pyenv exec pip install psutil readchar

# Встановлення requirements.txt якщо існує
if [ -f "requirements.txt" ]; then
    echo "Знайдено requirements.txt, встановлюю залежності..."
    pyenv exec pip install -r requirements.txt
fi

echo -e "\n========================================="
echo "Установка завершена!"
echo "========================================="
echo ""
echo "Для запуску BlockAssist використовуйте:"
echo "cd blockassist"
echo "pyenv exec python assistant.py"
echo ""
