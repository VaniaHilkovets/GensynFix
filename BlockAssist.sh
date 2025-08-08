#!/bin/bash
set -e

# Логирование ошибок в файл
exec 2> setup_error.log

# Проверка, что система использует apt (Debian/Ubuntu)
if ! command -v apt >/dev/null 2>&1; then
    echo "Ошибка: Этот скрипт предназначен для систем на базе Debian/Ubuntu с apt."
    exit 1
fi

# Проверка прав root (так как вы работаете от root)
if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: Скрипт должен запускаться от имени root."
    exit 1
fi

# Проверка VNC-окружения (для уверенности)
if [ -z "$DISPLAY" ]; then
    echo "Предупреждение: Переменная DISPLAY не установлена. Убедитесь, что вы в VNC-сессии."
fi

echo "[*] Обновление списка пакетов..."
apt update

echo "[*] Установка зависимостей для Python..."
apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
libffi-dev liblzma-dev python3-pip

echo "[*] Клонирование BlockAssist..."
cd /root
if [ -d "blockassist" ]; then
    echo "[*] Директория blockassist уже существует. Удалить? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
        rm -rf blockassist
    else
        echo "Скрипт остановлен."
        exit 1
    fi
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

echo "[*] Запуск setup.sh (Java + Malmo)..."
if [ -f "setup.sh" ]; then
    chmod +x setup.sh
    ./setup.sh
else
    echo "Ошибка: Файл setup.sh не найден."
    exit 1
fi

echo "[*] Установка pyenv..."
if ! command -v pyenv >/dev/null 2>&1; then
    curl -fsSL https://pyenv.run | bash
else
    echo "[*] pyenv уже установлен, пропускаем..."
fi

# Добавление pyenv в .bashrc, если еще не добавлено
if ! grep -q 'pyenv init' /root/.bashrc; then
    cat >> /root/.bashrc <<'EOL'
export PATH="/root/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOL
fi

# Применение изменений в текущей сессии
export PATH="/root/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "[*] Установка Python 3.10..."
pyenv install -s 3.10.12
pyenv global 3.10.12

echo "[*] Установка Python-пакетов..."
pip install --upgrade pip
pip install psutil readchar

echo "[*] Запуск BlockAssist..."
if [ -f "run.py" ]; then
    python run.py
else
    echo "Ошибка: Файл run.py не найден."
    exit 1
fi
