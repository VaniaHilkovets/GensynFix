#!/bin/bash
set -euo pipefail

# ===== Логирование ошибок =====
exec 2> /root/blockassist_setup_error.log
export DEBIAN_FRONTEND=noninteractive

echo "[*] Проверки..."
if ! command -v apt >/dev/null 2>&1; then
  echo "Ошибка: Нужен Debian/Ubuntu с apt."; exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Ошибка: запустите от root."; exit 1
fi
if [ -z "${DISPLAY:-}" ]; then
  echo "Предупреждение: DISPLAY не установлен. Убедитесь, что вы в VNC."
fi

echo "[*] Обновление пакетов..."
apt update -y

echo "[*] Базовые зависимости..."
apt install -y \
  make build-essential gcc g++ \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  curl git ca-certificates gnupg \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
  libffi-dev liblzma-dev python3 python3-venv python3-pip \
  unzip zip rsync pkg-config

# ===== Chromium (не Firefox) =====
echo "[*] Установка Chromium..."
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  apt install -y snapd || true
  if command -v snap >/dev/null 2>&1; then
    snap install chromium
  else
    # резервный вариант (иногда тянет snap-транзит пакет)
    apt install -y chromium-browser || apt install -y chromium || true
  fi
fi

# ===== SWAP, если отсутствует =====
if ! swapon --noheadings | grep -q . ; then
  echo "[*] Создание swap 8G..."
  fallocate -l 8G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ===== Node.js 20 через NVM (до любых yarn/npm шагов!) =====
echo "[*] Установка NVM и Node.js 20..."
export NVM_DIR="/root/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
# shellcheck disable=SC1090
. "$NVM_DIR/nvm.sh"
nvm install 20
nvm alias default 20
nvm use 20

# Yarn через corepack (рекомендовано для Node >=16)
echo "[*] Активация corepack/yarn..."
corepack enable || npm i -g yarn
yarn -v || true

# Чуть больше хипа для больших сборок
export NODE_OPTIONS="--max-old-space-size=4096"

# ===== BlockAssist =====
echo "[*] Клонирование BlockAssist..."
cd /root
rm -rf blockassist
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# На случай если setup.sh внутри дергает node/yarn — уже под NVM:
export PATH="$NVM_DIR/versions/node/$(nvm current)/bin:$PATH"

echo "[*] Запуск setup.sh (Java + Malmo)..."
if [ -f "./setup.sh" ]; then
  chmod +x ./setup.sh
  ./setup.sh
else
  echo "Ошибка: setup.sh не найден"; exit 1
fi

# ===== pyenv + Python 3.10.12 =====
echo "[*] Установка pyenv..."
rm -rf /root/.pyenv
curl -fsSL https://pyenv.run | bash

# shellcheck disable=SC2016
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

echo "[*] Установка Python 3.10.12 через pyenv..."
pyenv install -s 3.10.12
pyenv global 3.10.12

echo "[*] Обновление pip и базовые пакеты..."
pip install --upgrade pip
pip install psutil readchar

# ===== Ярлык Chromium на рабочем столе =====
echo "[*] Создание ярлыка Chromium..."
mkdir -p /root/Desktop
CHROME_BIN="chromium"
command -v chromium-browser >/dev/null 2>&1 && CHROME_BIN="chromium-browser"
cat > /root/Desktop/chromium.desktop <<EOL
[Desktop Entry]
Name=Chromium
Exec=${CHROME_BIN} %U
Type=Application
Icon=chromium
Terminal=false
EOL
chmod +x /root/Desktop/chromium.desktop || true

# ===== Запуск BlockAssist =====
echo "[*] Запуск BlockAssist..."
if [ -f "run.py" ]; then
  echo "Запускаем run.py. Если зависнет — нажмите ENTER пару раз в консоли."
  python run.py
else
  echo "Ошибка: run.py не найден"; exit 1
fi

echo "[✓] Готово."
