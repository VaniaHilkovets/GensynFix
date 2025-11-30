#!/bin/bash

# ==========================================
# Gensyn CodeAssist Manager v5.1 (Stable CF + Token Fix)
# ==========================================

set -euo pipefail

BASE_DIR="$HOME"
REPO_DIR="$BASE_DIR/codeassist"
REPO_URL="https://github.com/gensyn-ai/codeassist.git"
PORT=3000
TMUX_SESSION="codeassist_node"
TUNNEL_SESSION="codeassist_tunnel"

print_status() { echo -e "\n>>> $1"; }

install_node() {
    print_status "Обновление системы и установка зависимостей..."
    sudo apt-get update && sudo apt-get install -y docker.io python3-pip git tmux lsof curl
    sudo systemctl start docker
    
    # Установка uv (менеджер пакетов Python)
    if ! command -v uv &> /dev/null; then
        print_status "Установка uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source $HOME/.local/bin/env || export PATH="$HOME/.local/bin:$PATH"
    fi

    # Установка Cloudflare Tunnel (cloudflared)
    if ! command -v cloudflared &> /dev/null; then
        print_status "Установка Cloudflare Tunnel..."
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi

    if [ ! -d "$REPO_DIR" ]; then
        print_status "Клонирование репозитория..."
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    print_status "✅ Установка завершена."
}

run_auto() {
    echo ""
    echo "🔑 Введите ваш Hugging Face Token (если нужно):"
    read -s -p "Token: " HF_TOKEN
    echo ""

    # === ОЧИСТКА СТАРЫХ ПРОЦЕССОВ ===
    print_status "Очистка старых сессий..."
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    # Убиваем всё, что сидит на порту 3000
    sudo fuser -k $PORT/tcp 2>/dev/null || true

    # === ЗАПУСК СЕРВЕРА ===
    print_status "Запуск CodeAssist..."
    
    # Запускаем через uv run внутри tmux
    CMD="cd $REPO_DIR && $HOME/.local/bin/uv run run.py; read"
    tmux new-session -d -s "$TMUX_SESSION" "$CMD"

    print_status "Ждем инициализацию сервера..."
    
    local started=false
    local token_sent=false  # Флаг: отправляли ли мы уже токен
    local counter=0
    
    # === ЦИКЛ ОЖИДАНИЯ (До 5 минут) ===
    while [ $counter -lt 300 ]; do
        sleep 2
        counter=$((counter+1))
        
        # Читаем последние 100 строк логов
        LOGS=$(tmux capture-pane -pt "$TMUX_SESSION" -S -100)
        
        # 1. Авто-ввод токена (Срабатывает только 1 раз)
        if [ "$token_sent" = false ] && echo "$LOGS" | grep -q "HuggingFace token"; then
             tmux send-keys -t "$TMUX_SESSION" "$HF_TOKEN" Enter
             print_status "Токен отправлен. Ожидаем принятия..."
             token_sent=true  # Запоминаем, чтобы не спамить
             sleep 5
        fi

        # 2. Проверка успешного запуска (ищем заветную строку)
        if echo "$LOGS" | grep -q "CodeAssist Started" || echo "$LOGS" | grep -q "http://localhost:3000"; then
            print_status "✅ Сервер CodeAssist успешно запущен!"
            started=true
            break
        fi
        
        echo -n "."
    done

    if [ "$started" = false ]; then
        echo ""
        echo "❌ Сервер не запустился за 10 минут. Проверьте логи (пункт 3)."
        return
    fi

    # === ЗАПУСК ТУННЕЛЯ (Только если сервер работает) ===
    print_status "Запускаем стабильный Cloudflare туннель..."
    rm -f /tmp/tunnel.log
    
    # Запускаем cloudflared в фоне
    tmux new-session -d -s "$TUNNEL_SESSION" "cloudflared tunnel --url http://localhost:$PORT --no-autoupdate 2>&1 | tee /tmp/tunnel.log"
    
    print_status "Генерация ссылки..."
    sleep 5 
    
    # Парсим ссылку из логов (пробуем несколько раз)
    local link=""
    local link_attempts=0
    while [ -z "$link" ] && [ $link_attempts -lt 20 ]; do
        link=$(grep -o 'https://.*\.trycloudflare\.com' /tmp/tunnel.log | head -n1)
        if [ -z "$link" ]; then
            sleep 2
            echo -n "."
            link_attempts=$((link_attempts+1))
        fi
    done
    
    if [ -z "$link" ]; then
        echo "⚠️ Не удалось получить ссылку. Проверьте логи туннеля (пункт 4)."
    else
        echo ""
        echo "======================================="
        echo "🚀 ВАША ССЫЛКА: $link"
        echo "======================================="
    fi
    
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}

show_menu() {
    clear
    echo "=== CodeAssist Manager v5.1 (CF) ==="
    echo "1) Установить / Обновить (Deps + Cloudflared)"
    echo "2) Запустить (Auto)"
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
