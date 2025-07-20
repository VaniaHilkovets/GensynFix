#!/bin/bash

SCRIPT="./run_rl_swarm.sh"
TMP_LOG="/tmp/rlswarm_stdout.log"
MAX_IDLE=600  # 10 минут

KEYWORDS=(
  "BlockingIOError"
  "EOFError"
  "RuntimeError"
  "ConnectionResetError"
  "CUDA out of memory"
  "P2PDaemonError"
  "OSError"
  "error was detected while running rl-swarm"
  "Connection refused"
  "requests.exceptions.ConnectionError"
  "Identity from .* is already taken by another peer"
)

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
SWARM_PEM="$SCRIPT_DIR/swarm.pem"

kill_node_procs() {
  echo "[$(date)] Завершаем процессы из папки $SCRIPT_DIR..."

  # Убиваем процессы, использующие swarm.pem
  if [ -f "$SWARM_PEM" ]; then
    echo "[$(date)] Убиваем процессы, использующие $SWARM_PEM..."
    lsof "$SWARM_PEM" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | xargs -r kill -9
    sleep 1
  fi

  # Убиваем все процессы, чей cwd = SCRIPT_DIR
  for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    if [[ "$cwd" == "$SCRIPT_DIR" ]]; then
      echo "[$(date)] Убиваем процесс PID=$pid, cwd=$cwd"
      kill -9 "$pid" 2>/dev/null
    fi
  done

  # hivemind p2pd
  echo "[$(date)] Убиваем зависшие p2pd (hivemind)..."
  pgrep -f hivemind_cli/p2pd | xargs -r kill -9

  # modal next.js
  echo "[$(date)] Убиваем next build (modal-login)..."
  pgrep -f node_modules/.bin/next | xargs -r kill -9

  # modal-login
  echo "[$(date)] Убиваем modal-login процессы..."
  pgrep -f modal-login | xargs -r kill -9
}

while true; do
  echo "[$(date)] Запуск Gensyn-ноды..."
  rm -f "$TMP_LOG"

  if [ ! -f "$SWARM_PEM" ]; then
    echo "[$(date)] [ОШИБКА] swarm.pem не найден: $SWARM_PEM"
    echo "Сначала запусти ./run_rl_swarm.sh вручную и подтверди генерацию ключа"
    exit 1
  fi

  # запуск с автоответами
  ( sleep 1 && printf "n\n\n\n" ) | bash "$SCRIPT" 2>&1 | tee "$TMP_LOG" &
  PID=$!

  while kill -0 "$PID" 2>/dev/null; do
    sleep 5

    if [ -f "$TMP_LOG" ]; then
      current_mod=$(stat -c %Y "$TMP_LOG")
      now=$(date +%s)
      idle_time=$((now - current_mod))

      if (( idle_time > MAX_IDLE )); then
        echo "[$(date)] Лог не обновлялся $((MAX_IDLE/60)) мин. Перезапуск..."
        kill -9 "$PID" 2>/dev/null
        sleep 3
        kill_node_procs
        break
      fi
    fi

    for ERR in "${KEYWORDS[@]}"; do
      if grep -q "$ERR" "$TMP_LOG"; then
        echo "[$(date)] Найдено '$ERR'. Перезапуск..."
        kill -9 "$PID" 2>/dev/null
        sleep 3
        kill_node_procs
        break 2
      fi
    done
  done

  echo "[$(date)] Процесс завершён. Перезапуск через 3 секунды..."
  sleep 3
done
