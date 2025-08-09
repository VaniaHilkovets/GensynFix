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
if [ -d "blockassist" ]; then
    rm -rf blockassist
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Step 2: Install Java
echo -e "\n[2/5] Install Java 1.8.0_152..."
./setup.sh

# ВАЖНО: Активируем Java сразу после установки
export JAVA_PATH=/opt/zulu8.25.0.1-jdk8.0.152-linux_x64
export PATH=$JAVA_PATH/bin:$PATH

# Проверяем установку Java
if ! command -v java &> /dev/null; then
    echo "ОШИБКА: Java не найдена после установки!"
    exit 1
fi
echo "Java установлена: $(java -version 2>&1 | head -n 1)"

# Step 3: Install pyenv
echo -e "\n[3/5] Install pyenv..."
if [ -d "$HOME/.pyenv" ]; then
    rm -rf "$HOME/.pyenv"
fi
curl -fsSL https://pyenv.run | bash

# Добавляем pyenv в bashrc ЕСЛИ ЕЩЕ НЕТ
if ! grep -q 'export PYENV_ROOT="$HOME/.pyenv"' ~/.bashrc; then
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
fi

# Добавляем Java в bashrc ЕСЛИ ЕЩЕ НЕТ
if ! grep -q 'export JAVA_PATH=/opt/zulu8.25.0.1-jdk8.0.152-linux_x64' ~/.bashrc; then
    echo 'export JAVA_PATH=/opt/zulu8.25.0.1-jdk8.0.152-linux_x64' >> ~/.bashrc
    echo 'export PATH=$JAVA_PATH/bin:$PATH' >> ~/.bashrc
fi

# Активируем pyenv для текущей сессии
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Step 4: Install Python 3.10
echo -e "\n[4/5] Install Python 3.10..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

# Проверяем, установлен ли уже Python 3.10
if pyenv versions | grep -q "3.10"; then
    echo "Python 3.10 уже установлен"
else
    pyenv install 3.10
fi

pyenv global 3.10

# Активируем Python 3.10
eval "$(pyenv init -)"

# Step 5: Install psutil and readchar
echo -e "\n[5/5] Install psutil and readchar..."
~/.pyenv/shims/pip install psutil readchar

echo -e "\n========================================="
echo "Установка завершена!"
echo ""
echo "Теперь можно запустить BlockAssist:"
echo ""
echo "  cd ~/blockassist && python run.py"
echo ""
echo "Firefox установлен и ярлык создан на рабочем столе"
echo "========================================="

# Создаем скрипт запуска для удобства
cat > ~/blockassist/start.sh << 'EOF'
#!/bin/bash
export JAVA_PATH=/opt/zulu8.25.0.1-jdk8.0.152-linux_x64
export PATH=$JAVA_PATH/bin:$PATH
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
cd ~/blockassist
python run.py
EOF
chmod +x ~/blockassist/start.sh

echo -e "\nТакже создан скрипт быстрого запуска:"
echo "  ~/blockassist/start.sh"
