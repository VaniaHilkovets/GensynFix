#!/bin/bash

SCRIPT="./run_rl_swarm.sh"
TMP_LOG="/tmp/rlswarm_stdout.log"
MAX_IDLE=600  # 10 минут
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
SWARM_PEM="$SCRIPT_DIR/swarm.pem"

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

kill_node_procs() {
  echo "[$(date)] Убиваем процессы из $SCRIPT_DIR..."

  if [ -f "$SWARM_PEM" ]; then
    lsof "$SWARM_PEM" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | xargs -r kill -9
  fi

  for pid in $(ls /proc | grep -E '^[0-9]+$'); do
    cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || true)
    if [[ "$cwd" == "$SCRIPT_DIR" ]]; then
      kill -9 "$pid" 2>/dev/null
    fi
  done

  pgrep -f hivemind_cli/p2pd | xargs -r kill -9
  pgrep -f node_modules/.bin/next | xargs -r kill -9
  pgrep -f modal-login | xargs -r kill -9
}

while true; do
  echo "[$(date)] Запуск Gensyn-ноды..."
  rm -f "$TMP_LOG"

  if [ ! -f "$SWARM_PEM" ]; then
    echo "[$(date)] [ОШИБКА] swarm.pem не найден. Ждём 5 минут..."
    sleep 300
    continue
  fi

  (sleep 1 && printf "n\n\n\n") | bash "$SCRIPT" 2>&1 | tee "$TMP_LOG" &
  PID=$!

  while kill -0 "$PID" 2>/dev/null; do
    sleep 5

    if [ -f "$TMP_LOG" ]; then
      current_mod=$(stat -c %Y "$TMP_LOG")
      now=$(date +%s)
      idle_time=$((now - current_mod))

      if (( idle_time > MAX_IDLE )); then
        echo "[$(date)] Лог не обновляется $((MAX_IDLE/60)) мин. Перезапуск..."
        kill -9 "$PID"
        sleep 2
        kill_node_procs
        break
      fi
    fi

    for ERR in "${KEYWORDS[@]}"; do
      if grep -q "$ERR" "$TMP_LOG"; then
        echo "[$(date)] Найдено '$ERR'. Перезапуск..."
        kill -9 "$PID"
        sleep 2
        kill_node_procs
        break 2
      fi
    done
  done

  echo "[$(date)] Процесс завершён. Перезапуск через 3 секунды..."
  sleep 3
done
