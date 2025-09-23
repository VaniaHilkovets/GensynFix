#!/bin/bash

set -euo pipefail

apt update
apt install -y curl sudo tmux lsof git htop nvtop nano rsync

BASE_DIR="/root"
REPO_URL="https://github.com/VaniaHilkovets/GensynFix.git"
LOGIN_WAIT_TIMEOUT=10
LOG_FILE="/root/gensynfix_install.log"

# Логирование для отладки
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

show_menu() {
  echo -e "\n===== Меню GensynFix ====="
  echo "1) Установить ноды"
  echo "2) Логин по очереди"
  echo "3) Запуск всех нод в tmux"
  echo "4) Удалить все ноды"
  echo "5) Обновить GensynFix"
  echo "6) Выйти"
}

get_current_count() {
  COUNT=$(ls -d "$BASE_DIR"/GensynFix* 2>/dev/null | wc -l)
  if [ "$COUNT" -eq 0 ]; then
    log "[!] Нет установленных нод. Установите сначала (опция 1)."
    exit 1
  fi
  log "[+] Обнаружено $COUNT нод."
}

ensure_node_version() {
  log "[+] Проверяем Node.js..."

  # Проверяем текущую версию
  CURRENT_MAJOR=0
  if command -v node >/dev/null 2>&1; then
    CURRENT_MAJOR=$(node -v | sed 's/^v\([0-9]\+\).*/\1/')
    log "[+] Текущая версия Node.js: $(node -v), путь: $(which node)"
  fi

  # Удаляем все существующие версии Node.js и npm
  if [ "$CURRENT_MAJOR" -ne 20 ]; then
    log "[!] Обнаружены Node.js или npm. Удаляем все версии..."
    apt purge -y nodejs npm
    rm -rf /usr/local/bin/node /usr/local/bin/npm /usr/bin/node /usr/bin/npm /usr/local/lib/node_modules
    hash -r  # Очищаем кэш PATH
  fi

  # Устанавливаем Node.js 20
  log "[!] Устанавливаем Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
  apt update >> "$LOG_FILE" 2>&1
  apt install -y nodejs >> "$LOG_FILE" 2>&1

  # Проверяем версию
  INST_MAJOR=$(node -v | sed 's/^v\([0-9]\+\).*/\1/')
  if [ "$INST_MAJOR" -ne 20 ]; then
    log "[!] Не удалось установить Node.js 20. Текущая версия: $(node -v), путь: $(which node)"
    log "[!] Продолжаем с текущей версией, но это может вызвать проблемы."
  else
    log "[+] Node.js 20 установлен: $(node -v), путь: $(which node)"
  fi

  # Проверяем и устанавливаем pip3
  if ! command -v pip3 >/dev/null 2>&1; then
    log "[!] pip3 не найден. Устанавливаем..."
    apt update && apt install -y python3-pip
    ln -sf "$(which pip3)" /usr/bin/pip
  fi

  # Проверяем и устанавливаем jinja2
  JINJA_VERSION=$(pip3 show jinja2 2>/dev/null | grep Version | awk '{print $2}')
  if [ -z "$JINJA_VERSION" ] || [ "$(echo "$JINJA_VERSION" | awk -F. '{print ($1*1000+$2*10+$3)}')" -lt 3100 ]; then
    log "[!] Устанавливаем jinja2>=3.1.0..."
    pip3 install --upgrade jinja2 >> "$LOG_FILE" 2>&1
  fi
  log "[+] jinja2 версия: $(pip3 show jinja2 | grep Version | awk '{print $2}')"
}

run_setup() {
  ensure_node_version
  read -p "Сколько экземпляров нод установить? " COUNT
  log "[+] Клонируем GensynFix..."
  rm -rf "$BASE_DIR/GensynFix"
  git clone "$REPO_URL" "$BASE_DIR/GensynFix" >> "$LOG_FILE" 2>&1
  chmod +x "$BASE_DIR/GensynFix/"*.sh

  for i in $(seq 2 "$COUNT"); do
    cp -r "$BASE_DIR/GensynFix" "$BASE_DIR/GensynFix$i"
    chmod +x "$BASE_DIR/GensynFix$i/"*.sh
  done

  for i in $(seq 1 "$COUNT"); do
    FILE="$BASE_DIR/GensynFix"
    [ "$i" -gt 1 ] && FILE="$BASE_DIR/GensynFix$i"
    grep -q "LOGIN_PORT=" "$FILE/run_rl_swarm.sh" || echo "LOGIN_PORT=\${LOGIN_PORT:-3000}" >> "$FILE/run_rl_swarm.sh"
    sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|' "$FILE/run_rl_swarm.sh"
  done

  log "✅ Установка завершена."
  echo "✅ Установка завершена."
}

run_login_sequential() {
  ensure_node_version
  get_current_count

  for i in $(seq 1 "$COUNT"); do
    DIR="$BASE_DIR/GensynFix"
    [ "$i" -gt 1 ] && DIR="$BASE_DIR/GensynFix$i"
    PORT=$((2999 + i))

    log "[+] Запускаем tmux-сессию node$i на порту $PORT"
    tmux kill-session -t "node$i" 2>/dev/null
    tmux new-session -d -s "node$i" -n run "cd $DIR && LOGIN_PORT=$PORT ./run_rl_swarm.sh"

    echo -n "[*] Ждем запуска ноды... "
    while ! tmux capture-pane -t "node$i" -p | grep -q "Started server process"; do
      sleep 1
    done
    log "OK"
    echo "OK"

    log "[+] Запускаем проброс порта $PORT"
    TUNNEL_SESSION="tunnel$i"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null
    tmux new-session -d -s "$TUNNEL_SESSION" "ssh -o StrictHostKeyChecking=no -R 80:localhost:$PORT nokey@localhost.run | tee /tmp/tunnel$i.log"

    echo "[*] Ожидаем появления ссылки..."
    until LINK=$(grep -o 'https://[^ ]*' /tmp/tunnel$i.log | grep '\.lhr\.life' | head -n1); do
      sleep 5
    done
    log "➡️ Логин ноды $i: $LINK"
    echo "➡️ Логин ноды $i: $LINK"

    read -p "После успешного логина — жми Enter..."

    log "[+] Завершаем проброс $TUNNEL_SESSION"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null
  done

  log "⏳ Все ноды залогинены. Ждем $LOGIN_WAIT_TIMEOUT секунд..."
  echo "⏳ Все ноды залогинены. Ждем $LOGIN_WAIT_TIMEOUT секунд..."
  sleep "$LOGIN_WAIT_TIMEOUT"

  for i in $(seq 1 "$COUNT"); do
    tmux kill-session -t "tunnel$i" 2>/dev/null
    tmux kill-session -t "node$i" 2>/dev/null
  done
  log "[✓] Все сессии завершены. Готово к запуску."
  echo "[✓] Все сессии завершены. Готово к запуску."
}

run_start() {
  ensure_node_version
  get_current_count

  for i in $(seq 1 "$COUNT"); do
    DIR="$BASE_DIR/GensynFix"
    [ "$i" -gt 1 ] && DIR="$BASE_DIR/GensynFix$i"
    chmod +x "$DIR/auto_restart.sh" 2>/dev/null
  done

  [ ! -e /usr/bin/python ] && ln -sf /usr/bin/python3 /usr/bin/python
  SESSION="gensyn_start"
  tmux kill-session -t "$SESSION" 2>/dev/null

  for i in $(seq 1 "$COUNT"); do
    DIR="$BASE_DIR/GensynFix"
    [ "$i" -gt 1 ] && DIR="$BASE_DIR/GensynFix$i"
    PORT=$((2999 + i))
    CMD="cd $DIR && LOGIN_PORT=$PORT ./auto_restart.sh"

    if [ "$i" -eq 1 ]; then
      tmux new-session -d -s "$SESSION" -n "node$i" -x 800 -y 100 "$CMD"
    else
      tmux split-window -t "$SESSION" -h "$CMD"
    fi
  done

  tmux select-layout -t "$SESSION" tiled
  tmux attach -t "$SESSION"
}

run_update() {
  ensure_node_version
  get_current_count

  if [ -d "$BASE_DIR/GensynFix/.git" ]; then
    log "[+] Обновляем GensynFix..."
    pushd "$BASE_DIR/GensynFix" >/dev/null
    if ! git pull --ff-only; then
      log "[!] Не удалось выполнить fast-forward pull, сбрасываем..."
      git fetch origin
      git reset --hard origin/main
    fi
    popd >/dev/null
  else
    log "[!] Папка $BASE_DIR/GensynFix не является git-репозиторием."
  fi

  log "[+] Обновляем экземпляры GensynFix..."
  for i in $(seq 2 "$COUNT"); do
    DEST="$BASE_DIR/GensynFix$i"
    if [ -d "$DEST" ]; then
      log "[+] Обновляем $DEST"
      rsync -a --exclude='.git' --exclude='swarm.pem' --exclude='modal-login/temp-data/' "$BASE_DIR/GensynFix/" "$DEST/"
      chmod +x "$DEST/auto_restart.sh"
    fi
  done

  for i in $(seq 1 "$COUNT"); do
    FILE="$BASE_DIR/GensynFix"
    [ "$i" -gt 1 ] && FILE="$BASE_DIR/GensynFix$i"
    if [ -f "$FILE/run_rl_swarm.sh" ]; then
      grep -q "LOGIN_PORT=" "$FILE/run_rl_swarm.sh" || echo "LOGIN_PORT=\${LOGIN_PORT:-3000}" >> "$FILE/run_rl_swarm.sh"
      sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|' "$FILE/run_rl_swarm.sh"
    fi
  done

  log "✅ Обновление завершено."
  echo "✅ Обновление завершено."
}

while true; do
  show_menu
  read -p "Выбери [1-6]: " CHOICE
  case "$CHOICE" in
    1) run_setup ;;
    2) run_login_sequential ;;
    3) run_start ;;
    4)
      echo "Удалить ВСЁ (y/N)? "
      read -r YES
      if [[ "$YES" =~ ^[Yy]$ ]]; then
        log "💀 Убиваем процессы..."
        pkill -f GensynFix
        pkill -f run_rl_swarm.sh
        pkill -f auto_restart.sh
        pkill -f yarn
        pkill -f node
        pkill -f tmux

        log "🧹 Удаляем папки..."
        rm -rf /root/GensynFix*

        log "✅ Всё удалено."
        echo "✅ Всё удалено."
      else
        log "❌ Отменено."
        echo "❌ Отменено."
      fi
      ;;
    5) run_update ;;
    6) exit 0 ;;
    *) echo "Неверный выбор." ;;
  esac
done
