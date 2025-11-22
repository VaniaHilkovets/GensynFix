#!/bin/bash

# ==========================================
# Gensyn CodeAssist Manager v4.0 (Stable Wait)
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
    sudo apt-get update && sudo apt-get install -y docker.io python3-pip git tmux lsof
    sudo systemctl start docker
    
    if ! command -v uv &> /dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        source $HOME/.local/bin/env || export PATH="$HOME/.local/bin:$PATH"
    fi

    if [ ! -d "$REPO_DIR" ]; then
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    print_status "✅ Установлено."
}

run_auto() {
    echo ""
    echo "🔑 Введите ваш Hugging Face Token:"
    read -s -p "Token: " HF_TOKEN
    echo ""

    # Чистка
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    sudo fuser -k $PORT/tcp 2>/dev/null || true

    print_status "Запуск CodeAssist..."
    
    CMD="cd $REPO_DIR && $HOME/.local/bin/uv run run.py; read"
    tmux new-session -d -s "$TMUX_SESSION" "$CMD"

    print_status "Ждем запрос токена или старта..."
    
    local started=false
    local counter=0
    
    # ЦИКЛ ОЖИДАНИЯ (До 5 минут)
    while [ $counter -lt 300 ]; do
        sleep 2
        counter=$((counter+1))
        
        # Читаем логи
        LOGS=$(tmux capture-pane -pt "$TMUX_SESSION" -S -100)
        
        # 1. Вводим токен если просит
        if echo "$LOGS" | grep -q "HuggingFace token" && ! echo "$LOGS" | grep -q "CodeAssist Started"; then
             # Проверяем, не ввели ли мы его уже (чтобы не спамить)
             # Просто шлем один раз и ждем
             tmux send-keys -t "$TMUX_SESSION" "$HF_TOKEN" Enter
             print_status "Токен отправлен..."
             sleep 5
        fi

        # 2. Ищем заветную строчку успешного запуска
        if echo "$LOGS" | grep -q "CodeAssist Started" || echo "$LOGS" | grep -q "http://localhost:3000"; then
            print_status "✅ УСПЕХ! Сервер полностью загрузился."
            started=true
            break
        fi
        
        echo -n "."
    done

    if [ "$started" = false ]; then
        echo "❌ Сервер не запустился за 10 минут. Проверьте логи."
        return
    fi

    # 3. ТОЛЬКО ТЕПЕРЬ запускаем туннель
    print_status "Поднимаем туннель (теперь точно сработает)..."
    rm -f /tmp/tunnel.log
    
    # Используем Pinggy как запасной вариант, если localhost.run глючит, но пока оставим lhr
    tmux new-session -d -s "$TUNNEL_SESSION" "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -R 80:localhost:$PORT nokey@localhost.run 2>&1 | tee /tmp/tunnel.log"
    
    sleep 5
    local link=$(grep -o 'https://[^ ]*\.lhr\.life' /tmp/tunnel.log | head -n1)
    
    echo ""
    echo "======================================="
    echo "🚀 ВАША ССЫЛКА: $link"
    echo "======================================="
    read -p "Enter..."
}

show_menu() {
    clear
    echo "=== CodeAssist ==="
    echo "1) Установить"
    echo "2) Запустить"
    echo "3) Показать логи"
    echo "4) Выход"
}

while true; do
    show_menu
    read -p "> " c
    case "$c" in
        1) install_node ;;
        2) run_auto ;;
        3) tmux attach -t "$TMUX_SESSION" ;;
        4) exit 0 ;;
    esac
done
