#!/bin/bash

# BlockAssist автоматический установщик
# Запускать от root или с sudo

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     BlockAssist Автоустановщик               ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# 1. Обновляем систему
echo -e "${YELLOW}[1/10] Обновляем систему...${NC}"
apt update >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1
echo -e "${GREEN}✅ Система обновлена${NC}"

# 2. Базовые пакеты
echo -e "${YELLOW}[2/10] Проверяем базовые пакеты...${NC}"
PACKAGES=(git curl wget build-essential software-properties-common ca-certificates 
          gnupg lsb-release make libssl-dev zlib1g-dev libbz2-dev libreadline-dev 
          libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev 
          libffi-dev liblzma-dev python3-openssl netcat tmux)

NEED_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        NEED_INSTALL+=($pkg)
    fi
done

if [ ${#NEED_INSTALL[@]} -gt 0 ]; then
    echo "  Устанавливаем недостающие пакеты..."
    apt install -y "${NEED_INSTALL[@]}" >/dev/null 2>&1
fi
echo -e "${GREEN}✅ Базовые пакеты установлены${NC}"

# 3. Проверяем Node.js
echo -e "${YELLOW}[3/10] Проверяем Node.js...${NC}"
NODE_VERSION=$(node --version 2>/dev/null || echo "")
if [[ "$NODE_VERSION" =~ v1[8-9]\.|v2[0-9]\. ]]; then
    echo -e "${GREEN}✅ Node.js $NODE_VERSION${NC}"
else
    echo "  Устанавливаем Node.js 18..."
    # Удаляем старую версию если есть
    if [ ! -z "$NODE_VERSION" ]; then
        apt remove -y nodejs npm >/dev/null 2>&1
        apt purge -y nodejs npm >/dev/null 2>&1
        apt autoremove -y >/dev/null 2>&1
        rm -rf /usr/local/lib/node_modules
        rm -f /etc/apt/sources.list.d/nodesource.list*
    fi
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt install -y nodejs >/dev/null 2>&1
    echo -e "${GREEN}✅ Node.js $(node --version) установлен${NC}"
fi

# 4. Проверяем Yarn
echo -e "${YELLOW}[4/10] Проверяем Yarn...${NC}"
if command -v yarn >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Yarn $(yarn --version)${NC}"
else
    echo "  Устанавливаем Yarn..."
    npm install -g yarn >/dev/null 2>&1
    echo -e "${GREEN}✅ Yarn установлен${NC}"
fi

# 5. Клонируем/обновляем BlockAssist
echo -e "${YELLOW}[5/10] Проверяем репозиторий BlockAssist...${NC}"
cd /root
if [ -d "blockassist" ]; then
    cd blockassist
    git pull >/dev/null 2>&1
    echo -e "${GREEN}✅ Репозиторий обновлен${NC}"
else
    git clone https://github.com/gensyn-ai/blockassist.git >/dev/null 2>&1
    cd blockassist
    echo -e "${GREEN}✅ Репозиторий клонирован${NC}"
fi

# 6. Проверяем Java
echo -e "${YELLOW}[6/10] Проверяем Java...${NC}"
if [ -f "/opt/jdk1.8.0_152/bin/java" ]; then
    echo -e "${GREEN}✅ Java 1.8.0_152${NC}"
else
    echo "  Устанавливаем Java..."
    chmod +x setup.sh
    ./setup.sh >/dev/null 2>&1
    echo -e "${GREEN}✅ Java установлена${NC}"
fi

# 7. Проверяем Python
echo -e "${YELLOW}[7/10] Проверяем Python 3.10...${NC}"
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if [ ! -d "$PYENV_ROOT" ]; then
    echo "  Устанавливаем pyenv..."
    git clone https://github.com/pyenv/pyenv.git $PYENV_ROOT >/dev/null 2>&1
fi

eval "$(pyenv init -)"

if pyenv versions 2>/dev/null | grep -q "3.10"; then
    echo -e "${GREEN}✅ Python 3.10${NC}"
    pyenv global 3.10
else
    echo "  Устанавливаем Python 3.10..."
    pyenv install 3.10 >/dev/null 2>&1
    pyenv global 3.10
    echo -e "${GREEN}✅ Python 3.10 установлен${NC}"
fi

# 8. Python библиотеки
echo -e "${YELLOW}[8/10] Проверяем Python библиотеки...${NC}"
PYTHON_BIN="$PYENV_ROOT/versions/3.10.*/bin/python"
PIP_BIN="$PYENV_ROOT/versions/3.10.*/bin/pip"

NEED_INSTALL=false
if ! $PYTHON_BIN -c "import psutil" 2>/dev/null; then
    NEED_INSTALL=true
fi
if ! $PYTHON_BIN -c "import readchar" 2>/dev/null; then
    NEED_INSTALL=true
fi

if [ "$NEED_INSTALL" = true ]; then
    echo "  Устанавливаем библиотеки..."
    $PIP_BIN install --upgrade pip >/dev/null 2>&1
    $PIP_BIN install psutil readchar >/dev/null 2>&1
    echo -e "${GREEN}✅ Библиотеки установлены${NC}"
else
    echo -e "${GREEN}✅ Библиотеки установлены${NC}"
fi

# Создаем алиасы
if [ ! -L "/usr/local/bin/python" ] || [ ! -L "/usr/local/bin/pip" ]; then
    ln -sf $PYTHON_BIN /usr/local/bin/python
    ln -sf $PIP_BIN /usr/local/bin/pip
fi

# 9. Проверяем зависимости проекта
echo -e "${YELLOW}[9/10] Проверяем зависимости проекта...${NC}"
cd /root/blockassist
if [ ! -d "node_modules" ] || [ ! -f "yarn.lock" ]; then
    echo "  Устанавливаем зависимости..."
    yarn install >/dev/null 2>&1
    echo -e "${GREEN}✅ Зависимости установлены${NC}"
else
    echo -e "${GREEN}✅ Зависимости установлены${NC}"
fi

# 10. Добавляем в bashrc
echo -e "${YELLOW}[10/10] Настраиваем окружение...${NC}"
if ! grep -q "PYENV_ROOT" ~/.bashrc; then
    echo 'export PYENV_ROOT="/opt/pyenv"' >> ~/.bashrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    echo 'export PATH="/opt/jdk1.8.0_152/bin:$PATH"' >> ~/.bashrc
fi
echo -e "${GREEN}✅ Окружение настроено${NC}"

# Создаем скрипт запуска
cat > /root/blockassist/start.sh << 'EOF'
#!/bin/bash
export PATH="/opt/jdk1.8.0_152/bin:$PATH"
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
cd /root/blockassist
python run.py
EOF
chmod +x /root/blockassist/start.sh

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   УСТАНОВКА ЗАВЕРШЕНА!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Для запуска BlockAssist в tmux используйте команду:${NC}"
echo ""
echo -e "${BLUE}tmux new -s blockassist 'cd /root/blockassist && ./start.sh'${NC}"
echo ""
echo -e "${YELLOW}Полезные команды tmux:${NC}"
echo "  tmux attach -t blockassist    - подключиться к сессии"
echo "  tmux detach                   - отключиться (Ctrl+B, затем D)"
echo "  tmux kill-session -t blockassist - остановить"
echo ""
echo -e "${YELLOW}Для входа в Gensyn создайте туннель:${NC}"
echo -e "${BLUE}ssh -R 80:localhost:3000 nokey@localhost.run${NC}"
echo ""
