#!/bin/bash

# ==========================================
# Gensyn CodeAssist Manager v5.3 (Aggressive Cleanup)
# ==========================================

set -u

BASE_DIR="$HOME"
REPO_DIR="$BASE_DIR/codeassist"
REPO_URL="https://github.com/gensyn-ai/codeassist.git"
PORT=3000
TMUX_SESSION="codeassist_node"
TUNNEL_SESSION="codeassist_tunnel"

print_status() { echo -e "\n>>> $1"; }

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
    echo ""
    echo "🔑 Введите ваш Hugging Face Token (если нужно):"
    read -s -p "Token: " HF_TOKEN
    echo ""

    # === АГРЕССИВНАЯ ЗАЧИСТКА ===
    print_status "🧹 Зачистка портов и старых процессов..."
    
    # 1. Убиваем сессии tmux
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    
    # 2. Убиваем ВСЕ процессы cloudflared (чтобы не было зомби-туннелей)
    sudo pkill -9 -f cloudflared 2>/dev/null || true

    # 3. Проверяем, кто держит порт 3000 и убиваем его
    if lsof -i :$PORT -t >/dev/null 2>&1; then
        PID=$(lsof -i :$PORT -t)
        echo "⚠️ Порт $PORT занят процессом PID $PID. Убиваем..."
        sudo kill -9 $PID 2>/dev/null || true
    fi
    
    # На всякий случай контрольный выстрел через fuser
    sudo fuser -k -9 $PORT/tcp 2>/dev/null || true
    
    sleep 2
    print_status "✅ Порт свободен. Начинаем запуск."

    # === ЗАПУСК ===
    CMD="cd $REPO_DIR && $HOME/.local/bin/uv run run.py; read"
    tmux new-session -d -s "$TMUX_SESSION" "$CMD"

    print_status "Ждем инициализацию сервера..."
    
    local started=false
    local token_sent=false
    local counter=0
    
    while [ $counter -lt 300 ]; do
        sleep 2
        counter=$((counter+1))
        LOGS=$(tmux capture-pane -pt "$TMUX_SESSION" -S -100)
        
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
        echo -n "."
    done

    if [ "$started" = false ]; then
        echo ""
        echo "❌ Сервер не запустился за 10 минут."
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
            echo -n "."
            link_attempts=$((link_attempts+1))
        fi
    done
    
    if [ -z "$link" ]; then
        echo ""
        echo "⚠️ Ссылка не найдена. Проверьте логи туннеля (пункт 4)."
    else
        echo ""
        echo "======================================="
        echo "🚀 ВАША ССЫЛКА: $link"
        echo "======================================="
    fi
    
    read -p "Нажмите Enter..."
}

show_menu() {
    clear
    echo "=== CodeAssist Manager v5.3 (Aggressive) ==="
    echo "1) Установить / Обновить"
    echo "2) Запустить (Auto Kill Port)"
    echo "3) Показать логи сервера"
    echo "4) Показать логи туннеля"
    echo "5) Выход"
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
