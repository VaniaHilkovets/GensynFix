#!/bin/bash

set -euo pipefail

# Функция для безопасного выхода
safe_exit() {
    echo "[!] Скрипт завершен с ошибкой: $1"
    exit 1
}

# Обработка ошибок
trap 'safe_exit "Произошла неожиданная ошибка на строке $LINENO"' ERR

# Основные переменные
BASE_DIR="/root"
REPO_URL="https://github.com/VaniaHilkovets/GensynFix.git"
LOGIN_WAIT_TIMEOUT=10
NVM_DIR="$HOME/.nvm"

# Установка базовых пакетов
install_base_packages() {
    echo "[+] Обновляем систему и устанавливаем базовые пакеты..."
    apt update || safe_exit "Не удалось обновить пакеты"
    apt install -y curl sudo tmux lsof git htop nano rsync python3 python3-pip build-essential || safe_exit "Не удалось установить базовые пакеты"
    
    # Создаем символическую ссылку для python если её нет
    if [ ! -e /usr/bin/python ]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi
    
    # Создаем символическую ссылку для pip если её нет
    if [ ! -e /usr/bin/pip ]; then
        ln -s /usr/bin/pip3 /usr/bin/pip
    fi
}

# Установка NVM и Node.js 20
install_nvm_and_node() {
    echo "[+] Устанавливаем NVM..."
    
    # Удаляем старую версию NVM если есть
    rm -rf "$NVM_DIR"
    
    # Устанавливаем NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash || safe_exit "Не удалось установить NVM"
    
    # Загружаем NVM в текущую сессию
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # Добавляем NVM в bashrc если его там нет
    if ! grep -q "NVM_DIR" ~/.bashrc; then
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
    fi
    
    # Проверяем что NVM установлен
    if ! command -v nvm &> /dev/null; then
        safe_exit "NVM не был установлен корректно"
    fi
    
    echo "[+] Устанавливаем Node.js 20..."
    nvm install 20 || safe_exit "Не удалось установить Node.js 20"
    nvm use 20 || safe_exit "Не удалось переключиться на Node.js 20"
    nvm alias default 20 || safe_exit "Не удалось установить Node.js 20 по умолчанию"
    
    # Проверяем установку
    NODE_VERSION=$(node -v)
    echo "[+] Установлена версия Node.js: $NODE_VERSION"
    
    if [[ ! "$NODE_VERSION" =~ ^v20\. ]]; then
        safe_exit "Установлена неправильная версия Node.js: $NODE_VERSION"
    fi
}

# Установка Python зависимостей
install_python_deps() {
    echo "[+] Устанавливаем Python зависимости..."
    
    # Обновляем pip
    pip install --upgrade pip || safe_exit "Не удалось обновить pip"
    
    # Устанавливаем jinja2
    pip install --upgrade "jinja2>=3.1.0" || safe_exit "Не удалось установить jinja2"
    
    # Проверяем версию jinja2
    JINJA_VERSION=$(pip show jinja2 2>/dev/null | grep Version | awk '{print $2}' || echo "не найдена")
    echo "[+] Установлена версия jinja2: $JINJA_VERSION"
}

# Показать меню
show_menu() {
    echo -e "\n===== Меню GensynFix ====="
    echo "1) Установить ноду"
    echo "2) Логин ноды"
    echo "3) Запуск ноды в tmux"
    echo "4) Удалить ноду"
    echo "5) Обновить GensynFix"
    echo "6) Показать статус ноды"
    echo "7) Выйти"
}

# Проверить установлена ли нода
check_node_installed() {
    if [ ! -d "$BASE_DIR/GensynFix" ]; then
        echo "[!] Нода не установлена. Установите сначала (опция 1)."
        return 1
    fi
    echo "[+] Нода найдена."
    return 0
}

# Обеспечить загрузку NVM для всех операций
ensure_nvm() {
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
        nvm use 20 &>/dev/null || true
    else
        safe_exit "NVM не найден. Переустановите ноды (опция 1)"
    fi
}

# Проверить порт
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # порт занят
    else
        return 1  # порт свободен
    fi
}

# Установка ноды
run_setup() {
    echo "[+] Начинаем установку ноды..."
    
    install_base_packages
    install_nvm_and_node
    install_python_deps
    
    echo "[+] Клонируем GensynFix..."
    rm -rf "$BASE_DIR/GensynFix"
    
    git clone "$REPO_URL" "$BASE_DIR/GensynFix" || safe_exit "Не удалось клонировать репозиторий"
    
    # Делаем скрипты исполняемыми
    find "$BASE_DIR/GensynFix" -name "*.sh" -exec chmod +x {} \; || true
    
    # Настраиваем порт для ноды (используем порт 3000)
    DIR="$BASE_DIR/GensynFix"
    if [ -f "$DIR/run_rl_swarm.sh" ]; then
        # Добавляем переменную LOGIN_PORT в начало файла если её нет
        if ! grep -q "LOGIN_PORT=" "$DIR/run_rl_swarm.sh"; then
            sed -i '1i LOGIN_PORT=${LOGIN_PORT:-3000}' "$DIR/run_rl_swarm.sh"
        fi
        
        # Заменяем команду запуска yarn с указанием порта
        sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>\&1 \&|' "$DIR/run_rl_swarm.sh"
    fi
    
    echo "✅ Установка ноды завершена успешно."
}

# Логин ноды
run_login() {
    ensure_nvm
    
    if ! check_node_installed; then
        return 1
    fi
    
    DIR="$BASE_DIR/GensynFix"
    PORT=3000
    
    echo "[+] Начинаем логин ноды (порт $PORT)..."
    
    # Проверяем что порт свободен
    if check_port $PORT; then
        echo "[!] Порт $PORT уже занят. Освобождаем..."
        fuser -k $PORT/tcp 2>/dev/null || true
        sleep 2
    fi
    
    echo "[+] Запускаем tmux-сессию node на порту $PORT"
    tmux kill-session -t "node" 2>/dev/null || true
    
    # Запускаем ноду
    tmux new-session -d -s "node" -n run "cd $DIR && export NVM_DIR='$HOME/.nvm' && [ -s '$NVM_DIR/nvm.sh' ] && \. '$NVM_DIR/nvm.sh' && nvm use 20 && LOGIN_PORT=$PORT ./run_rl_swarm.sh"
    
    # Ждем запуска
    echo -n "[*] Ждем запуска ноды... "
    local attempts=0
    while [ $attempts -lt 60 ]; do
        if tmux capture-pane -t "node" -p 2>/dev/null | grep -q "Started server process\|Server listening\|ready"; then
            echo "OK"
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done
    
    if [ $attempts -eq 60 ]; then
        echo "TIMEOUT"
        echo "[!] Нода не запустилась за отведенное время"
        tmux capture-pane -t "node" -p | tail -20
        return 1
    fi
    
    # Запускаем проброс порта
    echo "[+] Запускаем проброс порта $PORT"
    TUNNEL_SESSION="tunnel"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    rm -f "/tmp/tunnel.log"
    
    tmux new-session -d -s "$TUNNEL_SESSION" "ssh -o StrictHostKeyChecking=no -R 80:localhost:$PORT nokey@localhost.run 2>&1 | tee /tmp/tunnel.log"
    
    # Ждем ссылку
    echo -n "[*] Ожидаем появления ссылки... "
    local link_attempts=0
    LINK=""
    while [ $link_attempts -lt 30 ]; do
        if [ -f "/tmp/tunnel.log" ]; then
            LINK=$(grep -o 'https://[^ ]*' "/tmp/tunnel.log" 2>/dev/null | grep '\.lhr\.life' | head -n1 || true)
            if [ -n "$LINK" ]; then
                echo "OK"
                break
            fi
        fi
        sleep 2
        link_attempts=$((link_attempts + 1))
    done
    
    if [ -z "$LINK" ]; then
        echo "TIMEOUT"
        echo "[!] Не удалось получить ссылку для логина"
        return 1
    fi
    
    echo -e "\n🔗 Логин ноды: $LINK"
    echo "Откройте эту ссылку в браузере для логина"
    
    read -p "После успешного логина нажмите Enter для продолжения..."
    
    # Завершаем проброс
    echo "[+] Завершаем проброс $TUNNEL_SESSION"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    rm -f "/tmp/tunnel.log"
    
    echo -e "\n⏳ Ждем $LOGIN_WAIT_TIMEOUT секунд перед очисткой..."
    sleep $LOGIN_WAIT_TIMEOUT
    
    # Очищаем сессию логина
    tmux kill-session -t "node" 2>/dev/null || true
    
    echo "✅ Логин завершен. Готово к запуску."
}

# Запуск ноды
run_start() {
    ensure_nvm
    
    if ! check_node_installed; then
        return 1
    fi
    
    echo "[+] Запускаем ноду..."
    
    DIR="$BASE_DIR/GensynFix"
    PORT=3000
    
    # Проверяем что все скрипты исполняемые
    find "$DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    SESSION="gensyn_node"
    tmux kill-session -t $SESSION 2>/dev/null || true
    
    # Формируем команду с загрузкой NVM
    CMD="cd $DIR && export NVM_DIR='$HOME/.nvm' && [ -s '$NVM_DIR/nvm.sh' ] && \. '$NVM_DIR/nvm.sh' && nvm use 20 && LOGIN_PORT=$PORT ./auto_restart.sh"
    
    tmux new-session -d -s $SESSION -n "node" -x 120 -y 30 "$CMD"
    
    echo "✅ Нода запущена в tmux сессии '$SESSION'"
    echo "Для подключения используйте: tmux attach -t $SESSION"
    echo "Для отключения без остановки: Ctrl+B, затем D"
    
    read -p "Подключиться к tmux сессии сейчас? (y/N): " ATTACH
    if [[ "$ATTACH" =~ ^[Yy]$ ]]; then
        tmux attach -t $SESSION
    fi
}

# Обновление
run_update() {
    ensure_nvm
    
    if ! check_node_installed; then
        return 1
    fi
    
    echo "[+] Обновляем GensynFix..."
    
    DIR="$BASE_DIR/GensynFix"
    
    # Обновляем папку
    if [ -d "$DIR/.git" ]; then
        echo "[+] Обновляем GensynFix из репозитория..."
        cd "$DIR"
        
        # Сохраняем важные файлы
        [ -f "swarm.pem" ] && cp "swarm.pem" "/tmp/swarm.pem.backup"
        
        if ! git pull --ff-only 2>/dev/null; then
            echo "[!] Выполняем принудительное обновление..."
            git fetch origin || safe_exit "Не удалось получить обновления"
            git reset --hard origin/$(git rev-parse --abbrev-ref HEAD) || safe_exit "Не удалось применить обновления"
        fi
        
        # Восстанавливаем важные файлы
        [ -f "/tmp/swarm.pem.backup" ] && cp "/tmp/swarm.pem.backup" "swarm.pem" && rm "/tmp/swarm.pem.backup"
        
        cd - >/dev/null
    else
        echo "[!] Папка $DIR не является git-репозиторием."
        return 1
    fi
    
    # Настраиваем порт заново
    find "$DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    if [ -f "$DIR/run_rl_swarm.sh" ]; then
        if ! grep -q "LOGIN_PORT=" "$DIR/run_rl_swarm.sh"; then
            sed -i '1i LOGIN_PORT=${LOGIN_PORT:-3000}' "$DIR/run_rl_swarm.sh"
        fi
        sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>\&1 \&|' "$DIR/run_rl_swarm.sh"
    fi
    
    echo "✅ Обновление завершено успешно."
}

# Показать статус ноды
show_status() {
    if ! check_node_installed; then
        return 1
    fi
    
    echo -e "\n===== Статус ноды ====="
    
    # Проверяем tmux сессии
    SESSIONS=$(tmux list-sessions 2>/dev/null | grep -E "(node|gensyn_node)" | awk -F: '{print $1}' || true)
    if [ -n "$SESSIONS" ]; then
        echo "Активные tmux сессии:"
        echo "$SESSIONS" | while read session; do
            echo "  - $session"
        done
    else
        echo "Нет активных tmux сессий"
    fi
    
    echo -e "\nПорт и процесс:"
    PORT=3000
    if check_port $PORT; then
        PID=$(lsof -ti:$PORT)
        echo "  Нода (порт $PORT): АКТИВНА (PID: $PID)"
    else
        echo "  Нода (порт $PORT): НЕАКТИВНА"
    fi
    
    echo -e "\nПапка ноды:"
    DIR="$BASE_DIR/GensynFix"
    if [ -d "$DIR" ]; then
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        echo "  $DIR: существует ($SIZE)"
        
        # Дополнительная информация
        if [ -f "$DIR/swarm.pem" ]; then
            echo "  Ключ swarm.pem: найден"
        else
            echo "  Ключ swarm.pem: НЕ НАЙДЕН"
        fi
        
        if [ -d "$DIR/logs" ]; then
            LOG_COUNT=$(ls -1 "$DIR/logs/" 2>/dev/null | wc -l)
            echo "  Логи: $LOG_COUNT файлов"
        fi
    else
        echo "  $DIR: НЕ СУЩЕСТВУЕТ"
    fi
}
            echo "  $DIR: НЕ СУЩЕСТВУЕТ"
        fi
    done
}

# Удаление ноды
run_cleanup() {
    echo "⚠️  Удалить ноду и все данные? (y/N):"
    read -r YES
    
    if [[ ! "$YES" =~ ^[Yy]$ ]]; then
        echo "❌ Отменено"
        return 0
    fi
    
    echo "💀 Останавливаем все процессы..."
    
    # Убиваем tmux сессии
    tmux list-sessions 2>/dev/null | grep -E "(node|gensyn_node|tunnel)" | awk -F: '{print $1}' | xargs -I{} tmux kill-session -t {} 2>/dev/null || true
    
    # Убиваем процессы по именам
    pkill -f GensynFix 2>/dev/null || true
    pkill -f run_rl_swarm.sh 2>/dev/null || true
    pkill -f auto_restart.sh 2>/dev/null || true
    
    # Освобождаем порт 3000
    fuser -k 3000/tcp 2>/dev/null || true
    
    sleep 3
    
    echo "🧹 Удаляем папку..."
    rm -rf "$BASE_DIR/GensynFix" 2>/dev/null || true
    rm -f /tmp/tunnel*.log 2>/dev/null || true
    
    echo "✅ Нода удалена успешно"
}

# Основной цикл
main() {
    echo "=== GensynFix Manager ==="
    echo "Версия: 2.0 (одна нода с NVM)"
    
    while true; do
        show_menu
        read -p "Выберите опцию [1-7]: " CHOICE
        
        case "$CHOICE" in
            1) run_setup ;;
            2) run_login ;;
            3) run_start ;;
            4) run_cleanup ;;
            5) run_update ;;
            6) show_status ;;
            7) echo "👋 До свидания!"; exit 0 ;;
            *) echo "❌ Неверный выбор. Введите число от 1 до 7." ;;
        esac
        
        echo -e "\nНажмите Enter для возврата в меню..."
        read -r
    done
}

# Запуск основной функции
main "$@"
