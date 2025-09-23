#!/bin/bash

# Логин ноды
run_login() {
    if ! check_node_installed; then
        return 1
    fi
    
    local DIR="$BASE_DIR/GensynFix"
    local PORT=3000
    
    echo "[+] Начинаем логин ноды (порт $PORT)..."
    
    # Проверяем что порт свободен
    if check_port $PORT; then
        echo "[!] Порт $PORT уже занят. Освобождаем..."
        fuser -k $PORT/tcp 2>/dev/null || true
        sleep 2
    fi
    
    echo "[+] Запускаем tmux-сессию node на порту $PORT"
    tmux kill-session -t "node" 2>/dev/null || true
    
    # Запускаем ноду (Node.js теперь доступен глобально)
    tmux new-session -d -s "node" -n run "cd $DIR && LOGIN_PORT=$PORT ./run_rl_swarm.sh"
    
    # Ждем запуска и появления строки о готовности к логину
    echo -n "[*] Ждем запуска ноды и готовности к логину... "
    local attempts=0
    local node_ready=false
    
    while [ $attempts -lt 60 ]; do
        if tmux capture-pane -t "node" -p 2>/dev/null | grep -q "Please open http://localhost:3000 in your host browser"; then
            echo "OK"
            node_ready=true
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
        # Показываем прогресс
        if [ $((attempts % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    if [ "$node_ready" = false ]; then
        echo " TIMEOUT"
        echo "[!] Нода не запустилась или не готова к логину"
        echo "[!] Последние строки из логов ноды:"
        tmux capture-pane -t "node" -p | tail -20
        return 1
    fi
    
    # Ждем еще пару секунд после появления строки
    echo "[*] Ждем стабилизации ноды..."
    sleep 3
    
    # Теперь запускаем проброс порта
    echo "[+] Запускаем проброс порта $PORT"
    local TUNNEL_SESSION="tunnel"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    rm -f "/tmp/tunnel.log"
    
    tmux new-session -d -s "$TUNNEL_SESSION" "ssh -o StrictHostKeyChecking=no -R 80:localhost:$PORT nokey@localhost.run 2>&1 | tee /tmp/tunnel.log"
    
    # Ждем ссылку
    echo -n "[*] Ожидаем появления ссылки для логина... "
    local link_attempts=0
    local LINK=""
    
    while [ $link_attempts -lt 30 ]; do
        if [ -f "/tmp/tunnel.log" ]; then
            # Ищем ссылку в логах
            LINK=$(grep -o 'https://[^ ]*' "/tmp/tunnel.log" 2>/dev/null | grep '\.lhr\.life' | head -n1 || true)
            if [ -n "$LINK" ]; then
                echo "OK"
                break
            fi
        fi
        sleep 2
        link_attempts=$((link_attempts + 1))
        # Показываем прогресс
        if [ $((link_attempts % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    if [ -z "$LINK" ]; then
        echo " TIMEOUT"
        echo "[!] Не удалось получить ссылку для логина"
        echo "[!] Последние строки из tunnel логов:"
        [ -f "/tmp/tunnel.log" ] && tail -10 "/tmp/tunnel.log"
        return 1
    fi
    
    # Выводим ссылку крупно и понятно
    echo ""
    echo "======================================="
    echo "🔗 ССЫЛКА ДЛЯ ЛОГИНА:"
    echo ""
    echo "  $LINK"
    echo ""
    echo "======================================="
    echo ""
    echo "📋 Инструкции:"
    echo "  1. Откройте эту ссылку в браузере"
    echo "  2. Выполните вход в систему"
    echo "  3. После успешного входа вернитесь сюда"
    echo ""
    
    read -p "После успешного логина нажмите Enter для продолжения..."
    
    # Завершаем проброс
    echo "[+] Завершаем проброс порта..."
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    rm -f "/tmp/tunnel.log"
    
    echo -e "\n⏳ Ждем $LOGIN_WAIT_TIMEOUT секунд для сохранения сессии..."
    sleep $LOGIN_WAIT_TIMEOUT
    
    # Очищаем сессию логина
    echo "[+] Останавливаем временную сессию ноды..."
    tmux kill-session -t "node" 2>/dev/null || true
    
    echo ""
    echo "✅ Логин завершен успешно!"
    echo "   Теперь можно запустить ноду (опция 3)"
}
