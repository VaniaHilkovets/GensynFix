#!/bin/bash

# ==========================================
# Gensyn CodeAssist Manager v5.7 (Anti-Staircase)
# ==========================================

set -u

BASE_DIR="$HOME"
REPO_DIR="$BASE_DIR/codeassist"
REPO_URL="https://github.com/gensyn-ai/codeassist.git"
PORT=3000
TMUX_SESSION="codeassist_node"
TUNNEL_SESSION="codeassist_tunnel"

# === ОБРАБОТКА CTRL+C ===
ctrl_c_handler() {
    echo -e "\r\n\033[1;31m>>> ОБНАРУЖЕН CTRL+C. ЗАВЕРШЕНИЕ РАБОТЫ... <<<\033[0m\r"
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    sudo pkill -9 -f cloudflared 2>/dev/null || true
    stty sane
    exit 1
}
trap ctrl_c_handler SIGINT

# ГЛАВНЫЙ ФИКС: Добавляем \r (возврат в начало) перед текстом и в конце
print_status() { echo -e "\r\n>>> $1\r"; }
print_msg() { echo -e "\r$1\r"; }

install_node() {
    print_status "Обновление системы и установка зависимостей..."
    sudo apt-get update && sudo apt-get install -y docker.io python3-pip git tmux lsof curl psmisc
    sudo systemctl start docker
    
    if ! command -v uv &> /dev/null; then
        print_status "Установка uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source $HOME/.local/bin/env || export PATH="$HOME/.local/bin:$PATH"
    fi

    if ! command -v cloudflared &> /dev/null; then
        print_status "Установка Cloudflare Tunnel..."
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi

    if [ ! -d "$REPO_DIR" ]; then
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    print_status "✅ Установка завершена."
}

run_auto() {
    stty sane
    print_msg ""
    print_msg "🔑 Введите ваш Hugging Face Token (если нужно):"
    
    # Читаем токен, затем принудительно переносим строку
    read -p "Token: " HF_TOKEN
    echo -e "\r" 
    
    print_status "🧹 Зачистка портов и старых процессов..."
    
    # Полностью глушим вывод команд убийства, чтобы они не ломали верстку
    tmux kill-session -t "$TMUX_SESSION" >/dev/null 2>&1 || true
    tmux kill-session -t "$TUNNEL_SESSION" >/dev/null 2>&1 || true
    sudo pkill -9 -f cloudflared >/dev/null 2>&1 || true

    if lsof -i :$PORT -t >/dev/null 2>&1; then
        PID=$(lsof -i :$PORT -t)
        print_msg "⚠️ Порт $PORT занят процессом PID $PID. Убиваем..."
        sudo kill -9 $PID >/dev/null 2>&1 || true
    fi
    
    sudo fuser -k -9 $PORT/tcp >/dev/null 2>&1 || true
    
    sleep 2
    print_status "✅ Порт свободен. Начинаем запуск."

    CMD="cd $REPO_DIR && $HOME/.local/bin/uv run run.py; read"
    tmux new-session -d -s "$TMUX_SESSION" "$CMD"

    print_status "Ждем инициализацию сервера (Таймаут 100 мин, Ctrl+C для отмены)..."
    
    local started=false
    local token_sent=false
    local counter=0
    
    while [ $counter -lt 3000 ]; do
        sleep 2
        counter=$((counter+1))
        LOGS=$(tmux capture-pane -pt "$TMUX_SESSION" -S -100 2>/dev/null)
        
        if [ "$token_sent" = false ] && echo "$LOGS" | grep -q "HuggingFace token"; then
             tmux send-keys -t "$TMUX_SESSION" "$HF_TOKEN" Enter
             print_status "Токен отправлен. Ожидаем..."
             token_sent=true
             sleep 5
        fi

        if echo "$LOGS" | grep -q "CodeAssist Started" || echo "$LOGS" | grep -q "http://localhost:3000"; then
            print_status "✅ Сервер CodeAssist успешно запущен!"
            started=true
            break
        fi
        echo -ne "\r.   " # Печатаем точку и возвращаемся в начало, чтобы не спамить
    done

    if [ "$started" = false ]; then
        print_msg ""
        print_msg "❌ Сервер не запустился за 100 минут."
        return
    fi

    print_status "Запускаем стабильный Cloudflare туннель..."
    rm -f /tmp/tunnel.log
    
    tmux new-session -d -s "$TUNNEL_SESSION" "cloudflared tunnel --url http://localhost:$PORT --no-autoupdate 2>&1 | tee /tmp/tunnel.log"
    
    print_status "Генерация ссылки..."
    sleep 5 
    
    local link=""
    local link_attempts=0
    
    while [ -z "$link" ] && [ $link_attempts -lt 20 ]; do
        link=$(grep -o 'https://.*\.trycloudflare\.com' /tmp/tunnel.log | head -n1 || true)
        
        if [ -z "$link" ]; then
            sleep 2
            echo -ne "\rПоиск ссылки... "
            link_attempts=$((link_attempts+1))
        fi
    done
    
    if [ -z "$link" ]; then
        print_msg ""
        print_msg "⚠️ Ссылка не найдена. Проверьте логи туннеля (пункт 4)."
    else
        print_msg ""
        print_msg "======================================="
        print_msg "🚀 ВАША ССЫЛКА: $link"
        print_msg "======================================="
    fi
    
    read -p "Нажмите Enter..."
}

show_menu() {
    clear
    print_msg "=== CodeAssist Manager v5.7 (Anti-Staircase) ==="
    print_msg "1) Установить / Обновить"
    print_msg "2) Запустить (Auto Kill Port)"
    print_msg "3) Показать логи сервера"
    print_msg "4) Показать логи туннеля"
    print_msg "5) Выход"
}

while true; do
    show_menu
    read -p "> " c
    case "$c" in
        1) install_node ;;
        2) run_auto ;;
        3) tmux attach -t "$TMUX_SESSION" ;;
        4) tmux attach -t "$TUNNEL_SESSION" ;;
        5) exit 0 ;;
    esac
done
