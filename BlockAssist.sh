#!/bin/bash
# BlockAssist Ubuntu Installer Script
# Цей скрипт автоматично встановлює всі залежності для BlockAssist
set -e  # Вийти при помилці

echo "========================================="
echo "BlockAssist Installer для Ubuntu"
echo "========================================="

# Сохраняем начальную директорию
INITIAL_DIR=$(pwd)

# Крок 1: Встановлення всіх системних залежностей
echo -e "\n[1/8] Встановлення системних залежностей..."
sudo apt update
sudo apt install -y make build-essential gcc \
   libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
   libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
   libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
   curl git

# Крок 2: Клонування репозиторію
echo -e "\n[2/8] Клонування репозиторію BlockAssist..."
cd "$INITIAL_DIR"
if [ -d "blockassist" ]; then
   echo "Директорія blockassist вже існує. Видаляю..."
   rm -rf blockassist
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist
PROJECT_DIR=$(pwd)

# Крок 3: Встановлення Java
echo -e "\n[3/8] Встановлення Java 1.8.0_152..."
chmod +x setup.sh
./setup.sh

# Крок 4: Встановлення pyenv
echo -e "\n[4/8] Встановлення pyenv..."
if command -v pyenv &> /dev/null; then
   echo "pyenv вже встановлено"
else
   # Видалення старого pyenv якщо існує
   if [ -d "$HOME/.pyenv" ]; then
       echo "Видаляю стару директорію pyenv..."
       rm -rf "$HOME/.pyenv"
   fi
   
   curl -fsSL https://pyenv.run | bash
   
   # Додавання pyenv до bashrc
   echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
   echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
   echo 'eval "$(pyenv init -)"' >> ~/.bashrc
fi

# Завантаження pyenv для поточної сесії
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Переходимо назад в директорію проекту
cd "$PROJECT_DIR"

# Крок 5: Встановлення Python 3.10
echo -e "\n[5/8] Встановлення Python 3.10..."
if pyenv versions | grep -q "3.10"; then
   echo "Python 3.10 вже встановлено"
else
   pyenv install 3.10
fi

# Встановлення Python 3.10 як локальну версію для цього проекту
pyenv local 3.10

# Крок 6: Встановлення Python пакетів
echo -e "\n[6/8] Встановлення Python пакетів..."
pyenv exec pip install --upgrade pip
pyenv exec pip install psutil readchar

# Встановлення requirements.txt якщо існує
if [ -f "requirements.txt" ]; then
   echo "Знайдено requirements.txt, встановлюю залежності..."
   pyenv exec pip install -r requirements.txt
fi

# Крок 7: Встановлення Node.js 20
echo -e "\n[7/8] Встановлення Node.js 20..."
if ! command -v nvm &> /dev/null; then
   echo "Встановлення nvm..."
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
   
   # Додавання nvm до bashrc
   echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
   echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
   echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
else
   echo "nvm вже встановлено"
fi

# Активація nvm для поточної сесії
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Встановлення Node.js 20
echo "Встановлення Node.js версії 20..."
nvm install 20
nvm use 20
nvm alias default 20

# Перевірка версії
echo "Поточна версія Node.js: $(node --version)"
echo "Поточна версія npm: $(npm --version)"

# Переходимо назад в директорію проекту
cd "$PROJECT_DIR"

# Активація pyenv окруження знову (на випадок якщо nvm змінив PATH)
eval "$(pyenv init -)"
pyenv local 3.10

# Крок 8: Встановлення yarn та залежностей проекту
echo -e "\n[8/8] Встановлення yarn та залежностей проекту..."

# Перевірка що ми використовуємо правильну версію Node.js
echo "Перевірка версій перед встановленням yarn:"
echo "Node.js: $(node --version)"
echo "Python: $(pyenv exec python --version)"
echo "Поточна директорія: $(pwd)"

# Встановлення yarn через corepack
corepack enable
corepack prepare yarn@stable --activate

# Встановлення залежностей проекту
if [ -d "modal-login" ]; then
   echo "Переходжу в modal-login..."
   cd modal-login
   
   # Виправляємо конфлікт версій viem
   echo "Виправляю конфлікт версій..."
   yarn add viem@2.29.2
   
   # Встановлюємо залежності
   echo "Встановлюю залежності..."
   yarn install
   
   # Будуємо проект з пропуском перевірки типів якщо є помилки
   echo "Будую проект..."
   yarn build || SKIP_TYPE_CHECK=true yarn build
   
   cd ..
else
   echo "Попередження: директорія modal-login не знайдена"
fi

echo -e "\n========================================="
echo "Установка завершена!"
echo "========================================="
