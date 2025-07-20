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
)

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"

kill_node_procs() {
  echo "[$(date)] Завершаем процессы ноды из папки $SCRIPT_DIR..."

  while read -r pid comm ppid pcomm; do
    if [ -d "/proc/$pid/cwd" ] && [ "$(readlink -f /proc/$pid/cwd)" = "$SCRIPT_DIR" ]; then
      if [[ "$comm" =~ ^(python|python3|bash|sh|node)$ && "$pcomm" =~ ^(bash|sh|run_rl_swarm.sh|node|npm)$ ]]; then
        echo "[$(date)] Убиваем PID=$pid ($comm) с PPID=$ppid ($pcomm)"
        kill -9 "$pid" 2>/dev/null
      else
        echo "[$(date)] Пропускаем PID=$pid ($comm) с PPID=$ppid ($pcomm) — не связан с нодой"
      fi
    fi
  done < <(
    ps -eo pid,comm,ppid --no-headers | while read pid comm ppid; do
      pcomm=$(ps -p "$ppid" -o comm= 2>/dev/null || echo "unknown")
      echo "$pid $comm $ppid $pcomm"
    done
  )

  echo "[$(date)] Убиваем зависшие процессы hivemind, modal-login, next.js..."

  # Точные процессы с grep -f:
  pgrep -f hivemind_cli/p2pd | xargs -r kill -9
  pgrep -f node_modules/.bin/next | xargs -r kill -9
  pgrep -f modal-login | xargs -r kill -9
  pgrep -f "rgym_exp.runner.swarm_launcher" | xargs -r kill -9
}

while true; do
  echo "[$(date)] Запуск Gensyn-ноды..."
  rm -f "$TMP_LOG"

  ( sleep 1 && printf "n\n\n\n" ) | bash "$SCRIPT" 2>&1 | tee "$TMP_LOG" &
  PID=$!

  while kill -0 "$PID" 2>/dev/null; do
    sleep 5

    if [ -f "$TMP_LOG" ]; then
      current_mod=$(stat -c %Y "$TMP_LOG")
      now=$(date +%s)
      idle_time=$((now - current_mod))

      if (( idle_time > MAX_IDLE )); then
        echo "[$(date)] Лог не обновлялся более $((MAX_IDLE/60)) минут. Перезапуск ноды..."
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
