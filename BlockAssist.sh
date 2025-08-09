#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Начинаем установку ===${NC}"

# Обновление системы и установка Firefox
echo -e "${YELLOW}Обновляем систему и устанавливаем Firefox...${NC}"
sudo apt update
sudo apt install firefox -y

# Создание ярлыка Firefox на рабочем столе
echo -e "${YELLOW}Создаем ярлык Firefox на рабочем столе...${NC}"
cp /usr/share/applications/firefox.desktop ~/Desktop/
chmod +x ~/Desktop/firefox.desktop

# Клонирование репозитория blockassist
echo -e "${YELLOW}Клонируем репозиторий blockassist...${NC}"
cd ~
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist

# Проверяем и выполняем setup.sh если он существует
if [ -f "setup.sh" ]; then
    echo -e "${YELLOW}Запускаем setup.sh...${NC}"
    chmod +x setup.sh
    ./setup.sh
else
    echo -e "${YELLOW}setup.sh не найден, пропускаем этот шаг${NC}"
fi

# Установка pyenv
echo -e "${YELLOW}Устанавливаем pyenv...${NC}"
curl -fsSL https://pyenv.run | bash

# Добавление pyenv в PATH (для текущей сессии)
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# Добавление pyenv в ~/.bashrc для постоянной активации
echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc

# Установка зависимостей для Python
echo -e "${YELLOW}Устанавливаем зависимости для компиляции Python...${NC}"
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

# Установка Python 3.10
echo -e "${YELLOW}Устанавливаем Python 3.10...${NC}"
pyenv install 3.10

# Установка Python 3.10 как глобальной версии
pyenv global 3.10

# Установка pip пакетов
echo -e "${YELLOW}Устанавливаем необходимые Python пакеты...${NC}"
pip install psutil readchar

# Установка Java для Minecraft/Malmo
echo -e "${YELLOW}Устанавливаем Java для Minecraft/Malmo...${NC}"
sudo apt update
sudo apt install -y openjdk-8-jdk

# Проверка и установка Java 17 (может потребоваться для новых версий Minecraft)
echo -e "${YELLOW}Устанавливаем Java 17 (может потребоваться для новых версий)...${NC}"
sudo apt install -y openjdk-17-jdk

# Установка дополнительных зависимостей для Malmo
echo -e "${YELLOW}Устанавливаем дополнительные зависимости для Malmo...${NC}"
sudo apt install -y libgl1-mesa-glx libegl1-mesa libxrandr2 libxss1 libxcursor1 libxcomposite1 libasound2 libxi6 libxtst6

# Установка xvfb для виртуального дисплея (если используется VNC)
echo -e "${YELLOW}Устанавливаем xvfb для виртуального дисплея...${NC}"
sudo apt install -y xvfb

# Активация виртуального окружения blockassist и установка requirements
echo -e "${YELLOW}Настраиваем Python окружение для blockassist...${NC}"
cd ~/blockassist

# Создаем виртуальное окружение если его нет
if [ ! -d "blockassist-venv" ]; then
    echo -e "${YELLOW}Создаем виртуальное окружение...${NC}"
    python -m venv blockassist-venv
fi

# Активируем виртуальное окружение
source blockassist-venv/bin/activate

# Обновляем pip и устанавливаем зависимости
pip install --upgrade pip
if [ -f "requirements.txt" ]; then
    echo -e "${YELLOW}Устанавливаем зависимости из requirements.txt...${NC}"
    pip install -r requirements.txt
fi

# Дополнительные пакеты которые могут потребоваться для Malmo
echo -e "${YELLOW}Устанавливаем дополнительные Python пакеты для Malmo...${NC}"
pip install malmo lxml pillow future

# Проверка установки Java
echo -e "${GREEN}Проверка установки Java:${NC}"
java -version
echo -e "${GREEN}Java 17:${NC}"
/usr/lib/jvm/java-17-openjdk-amd64/bin/java -version 2>&1 || echo "Java 17 не установлена"

# Вывод финальной команды
echo -e "${GREEN}=== Установка завершена! ===${NC}"
echo -e "${YELLOW}Для запуска BlockAssist используйте одну из команд:${NC}"
echo ""
echo -e "${GREEN}1. Обычный запуск:${NC}"
echo "   cd ~/blockassist && source blockassist-venv/bin/activate && python run.py"
echo ""
echo -e "${GREEN}2. С виртуальным дисплеем (рекомендуется для VNC):${NC}"
echo "   cd ~/blockassist && source blockassist-venv/bin/activate && xvfb-run -a python run.py"
echo ""
echo -e "${GREEN}3. С указанием конкретной версии Java:${NC}"
echo "   cd ~/blockassist && source blockassist-venv/bin/activate && JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64 python run.py"
echo ""
echo -e "${YELLOW}Если возникнут проблемы:${NC}"
echo "- Проверьте логи: cat ~/blockassist/logs/malmo.log"
echo "- Убедитесь, что виртуальное окружение активировано"
echo "- Попробуйте другую версию Java (8 или 17)"
echo ""
echo -e "${YELLOW}Примечание: Возможно, потребуется перезапустить терминал или выполнить:${NC}"
echo -e "${GREEN}source ~/.bashrc${NC}"
echo -e "${YELLOW}чтобы активировать pyenv${NC}"
