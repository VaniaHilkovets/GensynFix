#!/bin/bash
set -e

# Логирование ошибок
exec 2> /root/blockassist_setup_error.log

# Проверка, что система использует apt
if ! command -v apt >/dev/null 2>&1; then
    echo "Ошибка: Скрипт предназначен для Debian/Ubuntu с apt."
    exit 1
fi

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ошибка: Запустите скрипт от имени root."
    exit 1
fi

# Проверка VNC
if [ -z "$DISPLAY" ]; then
    echo "Предупреждение: Переменная DISPLAY не установлена. Убедитесь, что вы в VNC."
fi

echo "[*] Обновление пакетов..."
apt update -y || { echo "Ошибка: Не удалось обновить пакеты."; exit 1; }

echo "[*] Установка зависимостей для Python..."
apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
libffi-dev liblzma-dev python3-pip || { echo "Ошибка: Не удалось установить зависимости."; exit 1; }

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
if ! git clone https://github.com/gensyn-ai/blockassist.git; then
    echo "Ошибка: Не удалось клонировать репозиторий."
    exit 1
fi
cd blockassist

echo "[*] Запуск setup.sh (Java + Malmo)..."
if [ -f "setup.sh" ]; then
    chmod +x setup.sh
    if ! ./setup.sh; then
        echo "Ошибка: Не удалось выполнить setup.sh. Проверьте /root/blockassist_setup_error.log."
        exit 1
    fi
else
    echo "Ошибка: Файл setup.sh не найден."
    exit 1
fi

echo "[*] Установка pyenv..."
if ! command -v pyenv >/dev/null 2>&1; then
    if ! curl -fsSL https://pyenv.run | bash; then
        echo "Ошибка: Не удалось установить pyenv."
        exit 1
    fi
else
    echo "[*] pyenv уже установлен, пропускаем..."
fi

# Настройка pyenv
if ! grep -q 'pyenv init' /root/.bashrc; then
    cat >> /root/.bashrc <<'EOL'
export PATH="/root/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
EOL
fi
export PATH="/root/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

echo "[*] Установка Python 3.10.12..."
if ! pyenv install -s 3.10.12; then
    echo "Ошибка: Не удалось установить Python 3.10.12."
    exit 1
fi
pyenv global 3.10.12

echo "[*] Установка Python-пакетов..."
if ! pip install --upgrade pip; then
    echo "Ошибка: Не удалось обновить pip."
    exit 1
fi
if ! pip install psutil readchar; then
    echo "Ошибка: Не удалось установить пакеты psutil и readchar."
    exit 1
fi

echo "[*] Запуск BlockAssist..."
if [ -f "run.py" ]; then
    echo "Запускаем run.py. Если зависнет, нажмите ENTER несколько раз."
    python run.py
else
    echo "Ошибка: Файл run.py не найден."
    exit 1
fi
