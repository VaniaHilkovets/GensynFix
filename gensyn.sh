#!/bin/bash

set -euo pipefail

apt update
apt install -y curl sudo tmux lsof git htop nvtop nano rsync

BASE_DIR="/root"
REPO_URL="https://github.com/VaniaHilkovets/GensynFix.git"
LOGIN_WAIT_TIMEOUT=10

show_menu() {
  echo -e "\n===== Меню GensynFix ====="
  echo "1) Установить ноды"
  echo "2) Логин по очереди (одна нода -> проброс -> подтверждение)"
  echo "3) Запуск всех нод в tmux"
  echo "4) Удалить всё ноды"
  echo "5) Обновить GensynFix"
  echo "6) Выйти"
}

get_current_count() {
  COUNT=$(ls -d "$BASE_DIR"/GensynFix* 2>/dev/null | wc -l)
  if [ "$COUNT" -eq 0 ]; then
    echo "[!] Нет установленных нод. Установите сначала (опция 1)."
    exit 1
  fi
  echo "[+] Обнаружено $COUNT нод."
}

ensure_node_version() {
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
  fi
  if ! command -v node &>/dev/null || [ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 20 ]; then
    if ! command -v nvm &>/dev/null; then
      echo "[!] Устанавливаем NVM..."
      curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
      source "$NVM_DIR/nvm.sh"
    fi
    echo "[!] Устанавливаем Node.js >= 20..."
    nvm install 20
    nvm alias default 20
    nvm use default
  fi

  if ! command -v pip &>/dev/null && ! command -v pip3 &>/dev/null; then
    echo "[!] pip не найден. Устанавливаем..."
    apt update && apt install -y python3-pip || {
      echo "[X] Ошибка установки pip"
      exit 1
    }
    ln -sf "$(which pip3)" /usr/bin/pip
  fi
}

run_setup() {
  ensure_node_version
  read -p "Сколько экземпляров нод установить? " COUNT
  echo "[+] Клонируем GensynFix..."
  rm -rf "$BASE_DIR/GensynFix"
  git clone "$REPO_URL" "$BASE_DIR/GensynFix"
  chmod +x "$BASE_DIR/GensynFix/"*.sh

  for i in $(seq 2 $COUNT); do
    cp -r "$BASE_DIR/GensynFix" "$BASE_DIR/GensynFix$i"
    chmod +x "$BASE_DIR/GensynFix$i/"*.sh
  done

  for i in $(seq 1 $COUNT); do
    FILE="$BASE_DIR/GensynFix"
    [[ $i -gt 1 ]] && FILE="$BASE_DIR/GensynFix$i"

    grep -q "LOGIN_PORT=" "$FILE/run_rl_swarm.sh" || sed -i '1i LOGIN_PORT=${LOGIN_PORT:-3000}' "$FILE/run_rl_swarm.sh"
    sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>\&1 \&|' "$FILE/run_rl_swarm.sh"
  done

  echo "✅ Установка завершена."
}

run_login_sequential() {
  ensure_node_version
  get_current_count

  for i in $(seq 1 $COUNT); do
    DIR="$BASE_DIR/GensynFix"
    [[ $i -gt 1 ]] && DIR="$BASE_DIR/GensynFix$i"
    PORT=$((2999 + i))

    echo "[+] Запускаем tmux-сессию node$i на порту $PORT"
    tmux kill-session -t "node$i" 2>/dev/null || true
    tmux new-session -d -s "node$i" -n run "cd $DIR && LOGIN_PORT=$PORT ./run_rl_swarm.sh"

    echo -n "[*] Ждем запуска ноды... "
    while ! tmux capture-pane -t "node$i" -p | grep -q "Started server process"; do
      sleep 1
    done
    echo "OK"

    echo "[+] Запускаем проброс порта $PORT"
    TUNNEL_SESSION="tunnel$i"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$TUNNEL_SESSION" "ssh -o StrictHostKeyChecking=no -R 80:localhost:$PORT nokey@localhost.run | tee /tmp/tunnel$i.log"

    echo "[*] Ожидаем появления ссылки..."
    until LINK=$(grep -o 'https://[^ ]*' /tmp/tunnel$i.log | grep '\.lhr\.life' | head -n1); do
      sleep 5
    done
    echo -e "\n➡️  Логин ноды $i: $LINK"

    read -p "После успешного логина — жми Enter..."

    echo "[+] Завершаем проброс $TUNNEL_SESSION"
    tmux kill-session -t "$TUNNEL_SESSION" 2>/dev/null || true
  done

  echo "⏳ Все ноды залогинены. Ждем $LOGIN_WAIT_TIMEOUT секунд перед очисткой..."
  sleep $LOGIN_WAIT_TIMEOUT

  for i in $(seq 1 $COUNT); do
    tmux kill-session -t "tunnel$i" 2>/dev/null || true
    tmux kill-session -t "node$i" 2>/dev/null || true
  done
  echo "[✓] Все сессии завершены. Готово к запуску."
}

run_start() {
  ensure_node_version
  get_current_count

  for i in $(seq 1 $COUNT); do
    DIR="$BASE_DIR/GensynFix"
    [[ $i -gt 1 ]] && DIR="$BASE_DIR/GensynFix$i"
    chmod +x "$DIR/auto_restart.sh" 2>/dev/null || true
  done

  if [ ! -e /usr/bin/python ]; then
    ln -s /usr/bin/python3 /usr/bin/python
  fi
  SESSION="gensyn_start"
  tmux kill-session -t $SESSION 2>/dev/null || true

  for i in $(seq 1 $COUNT); do
    DIR="$BASE_DIR/GensynFix"
    [[ $i -gt 1 ]] && DIR="$BASE_DIR/GensynFix$i"
    PORT=$((2999 + i))
    CMD="cd $DIR && LOGIN_PORT=$PORT ./auto_restart.sh"

    if [[ $i -eq 1 ]]; then
      tmux new-session -d -s $SESSION -n node$i -x 800 -y 100 "$CMD"
    else
      tmux split-window -t $SESSION -h "$CMD"
    fi
  done

  tmux select-layout -t $SESSION tiled
  tmux attach -t $SESSION
}

run_update() {
  ensure_node_version
  get_current_count

  if [ -d "$BASE_DIR/GensynFix/.git" ]; then
    echo "[+] Обновляем основную папку GensynFix из репозитория..."
    pushd "$BASE_DIR/GensynFix" >/dev/null
    if ! git pull --ff-only; then
      echo "[!] Не удалось выполнить fast-forward pull, выполняем принудительное обновление..."
      git fetch origin
      git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
    fi
    popd >/dev/null
  else
    echo "[!] Папка $BASE_DIR/GensynFix не является git‑репозиторием. Обновление не выполнено."
  fi

  echo "[+] Обновляем экземпляры GensynFix..."
  for i in $(seq 2 $COUNT); do
    DEST="$BASE_DIR/GensynFix$i"
    if [ -d "$DEST" ]; then
      echo "[+] Обновляем содержимое $DEST"
      rsync -a \
        --exclude='.git' \
        --exclude='swarm.pem' \
        --exclude='modal-login/temp-data/' \
        "$BASE_DIR/GensynFix/" "$DEST/"
      chmod +x "$DEST/auto_restart.sh"
    fi
  done

  for i in $(seq 1 $COUNT); do
    FILE="$BASE_DIR/GensynFix"
    [[ $i -gt 1 ]] && FILE="$BASE_DIR/GensynFix$i"
    if [ -f "$FILE/run_rl_swarm.sh" ]; then
      grep -q "LOGIN_PORT=" "$FILE/run_rl_swarm.sh" || sed -i '1i LOGIN_PORT=${LOGIN_PORT:-3000}' "$FILE/run_rl_swarm.sh"
      sed -i 's|yarn start >> "$ROOT/logs/yarn.log" 2>&1 &|PORT=$LOGIN_PORT yarn start >> "$ROOT/logs/yarn.log" 2>\&1 \&|' "$FILE/run_rl_swarm.sh"
    fi
  done

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
      echo "Удалить ВСЁ (y/N)?"
      read -r YES
      if [[ "$YES" =~ ^[Yy]$ ]]; then
        echo "💀 Убиваем все процессы, связанные с GensynFix..."
        pkill -f GensynFix || true
        pkill -f run_rl_swarm.sh || true
        pkill -f auto_restart.sh || true
        pkill -f yarn || true
        pkill -f node || true
        pkill -f tmux || true

        echo "🧹 Удаляем все папки GensynFix..."
        shopt -s nullglob
        rm -rf /root/GensynFix*

        echo "✅ Всё удалено"
      else
        echo "❌ Отменено"
      fi
      ;;
    5) run_update ;;
    6) exit 0 ;;
    *) echo "Неверный выбор" ;;
  esac
done
