#!/bin/bash

# BlockAssist автоматический установщик с исправлениями
# Запускать от root или с sudo

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     BlockAssist Автоустановщик       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
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
          libffi-dev liblzma-dev python3-openssl netcat-openbsd tmux)

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
if [[ "$NODE_VERSION" =~ v2[0-9]\. ]]; then
    echo -e "${GREEN}✅ Node.js $NODE_VERSION${NC}"
else
    echo "  Устанавливаем Node.js 20..."
    # Удаляем старую версию если есть
    if [ ! -z "$NODE_VERSION" ]; then
        apt remove -y nodejs npm >/dev/null 2>&1
        apt purge -y nodejs npm >/dev/null 2>&1
        apt autoremove -y >/dev/null 2>&1
        rm -rf /usr/local/lib/node_modules
        rm -f /etc/apt/sources.list.d/nodesource.list*
    fi
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
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
# Проверяем стандартный путь
if [ -f "/opt/jdk1.8.0_152/bin/java" ]; then
    echo -e "${GREEN}✅ Java 1.8.0_152${NC}"
else
    echo "  Устанавливаем Java..."
    cd /root/blockassist
    chmod +x setup.sh
    ./setup.sh >/dev/null 2>&1
    
    # Ищем где установилась Java (может быть Zulu)
    JAVA_INSTALL_PATH=$(find /opt -name "java" -type f | grep "bin/java" | grep -E "(jdk|zulu)" | head -1)
    
    if [ ! -z "$JAVA_INSTALL_PATH" ]; then
        JAVA_HOME_PATH=$(dirname $(dirname "$JAVA_INSTALL_PATH"))
        echo "  Java найдена в: $JAVA_HOME_PATH"
        
        # Создаем символическую ссылку на стандартный путь
        if [ ! -L "/opt/jdk1.8.0_152" ]; then
            echo "  Создаем символическую ссылку..."
            ln -s "$JAVA_HOME_PATH" /opt/jdk1.8.0_152
        fi
        echo -e "${GREEN}✅ Java установлена${NC}"
    else
        echo -e "${RED}❌ Ошибка установки Java. Пробуем еще раз...${NC}"
        ./setup.sh
    fi
fi

# Добавляем Java в PATH сразу
export PATH="/opt/jdk1.8.0_152/bin:$PATH"
export JAVA_HOME="/opt/jdk1.8.0_152"

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

# 8. Python библиотеки и виртуальное окружение
echo -e "${YELLOW}[8/10] Настраиваем Python окружение...${NC}"
cd /root/blockassist

# Устанавливаем venv для Python
PYTHON_BIN="$PYENV_ROOT/versions/3.10.*/bin/python"
PIP_BIN="$PYENV_ROOT/versions/3.10.*/bin/pip"

# Устанавливаем virtualenv
$PIP_BIN install --upgrade pip >/dev/null 2>&1
$PIP_BIN install virtualenv >/dev/null 2>&1

# Создаем виртуальное окружение если его нет
if [ ! -d "blockassist-venv" ]; then
    echo "  Создаем виртуальное окружение..."
    $PYTHON_BIN -m venv blockassist-venv
fi

# Активируем venv и устанавливаем библиотеки
source blockassist-venv/bin/activate
pip install --upgrade pip >/dev/null 2>&1
pip install psutil readchar >/dev/null 2>&1

# Устанавливаем зависимости проекта если есть requirements.txt
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt >/dev/null 2>&1
fi

deactivate

echo -e "${GREEN}✅ Python окружение настроено${NC}"

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

# Создаем профиль для BlockAssist
cat > /etc/profile.d/blockassist.sh << 'EOF'
export JAVA_HOME="/opt/jdk1.8.0_152"
export PATH="/opt/jdk1.8.0_152/bin:$PATH"
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if [ -f "$PYENV_ROOT/bin/pyenv" ]; then
    eval "$(pyenv init -)"
fi
EOF
chmod +x /etc/profile.d/blockassist.sh

# Добавляем в bashrc если еще нет
if ! grep -q "PYENV_ROOT" ~/.bashrc; then
    echo 'export PYENV_ROOT="/opt/pyenv"' >> ~/.bashrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    echo 'export JAVA_HOME="/opt/jdk1.8.0_152"' >> ~/.bashrc
    echo 'export PATH="/opt/jdk1.8.0_152/bin:$PATH"' >> ~/.bashrc
fi

# Настраиваем правильные пути для скриптов проекта
cd /root/blockassist
if [ -f "scripts/venv_setup.sh" ]; then
    # Исправляем пути в venv_setup.sh
    sed -i 's|pyenv which python|/opt/pyenv/bin/pyenv which python|g' scripts/venv_setup.sh
    sed -i '1i export PYENV_ROOT="/opt/pyenv"' scripts/venv_setup.sh
    sed -i '2i export PATH="$PYENV_ROOT/bin:$PATH"' scripts/venv_setup.sh
    sed -i '3i eval "$(pyenv init -)"' scripts/venv_setup.sh
fi

echo -e "${GREEN}✅ Окружение настроено${NC}"

# Создаем скрипт запуска
cat > /root/blockassist/start.sh << 'EOF'
#!/bin/bash

# Настраиваем окружение
export JAVA_HOME="/opt/jdk1.8.0_152"
export PATH="/opt/jdk1.8.0_152/bin:$PATH"
export PYENV_ROOT="/opt/pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# Инициализируем pyenv
if [ -f "$PYENV_ROOT/bin/pyenv" ]; then
    eval "$(pyenv init -)"
fi

# Переходим в директорию проекта
cd /root/blockassist

# Проверяем Java с полным путем
if [ ! -f "/opt/jdk1.8.0_152/bin/java" ]; then
    echo "❌ Java не найдена в /opt/jdk1.8.0_152/bin/java"
    echo "Попробуйте установить Java вручную:"
    echo "cd /root/blockassist && ./setup.sh"
    exit 1
fi

# Проверяем что Java работает
if ! /opt/jdk1.8.0_152/bin/java -version >/dev/null 2>&1; then
    echo "❌ Java установлена но не работает!"
    exit 1
fi

# Проверяем Python
if ! command -v python >/dev/null 2>&1; then
    # Пробуем использовать python из pyenv напрямую
    if [ -f "$PYENV_ROOT/versions/3.10.*/bin/python" ]; then
        export PATH="$PYENV_ROOT/versions/3.10.*/bin:$PATH"
    else
        echo "❌ Python не найден!"
        exit 1
    fi
fi

# Активируем виртуальное окружение если есть
if [ -d "blockassist-venv" ]; then
    source blockassist-venv/bin/activate
fi

# Выводим версии для отладки
echo "Java версия: $(/opt/jdk1.8.0_152/bin/java -version 2>&1 | head -1)"
echo "Python версия: $(python --version)"
echo "Путь к Java: $(which java)"
echo "Путь к Python: $(which python)"
echo ""

# Запускаем программу
echo "Запускаем BlockAssist..."
python run.py
EOF
chmod +x /root/blockassist/start.sh

# Создаем алиас для быстрого запуска
cat > /root/run_blockassist.sh << 'EOF'
#!/bin/bash
tmux new -s blockassist 'cd /root/blockassist && ./start.sh'
EOF
chmod +x /root/run_blockassist.sh

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   УСТАНОВКА ЗАВЕРШЕНА!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Для запуска BlockAssist используйте одну из команд:${NC}"
echo ""
echo -e "${BLUE}1. Быстрый запуск в tmux:${NC}"
echo -e "   ${GREEN}/root/run_blockassist.sh${NC}"
echo ""
echo -e "${BLUE}2. Запуск без tmux (для тестов):${NC}"
echo -e "   ${GREEN}cd /root/blockassist && ./start.sh${NC}"
echo ""
