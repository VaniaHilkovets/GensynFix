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
    # Проверяем, что cwd совпадает с папкой скрипта
    if [ -d "/proc/$pid/cwd" ] && [ "$(readlink -f /proc/$pid/cwd)" = "$SCRIPT_DIR" ]; then
      # Ограничиваем завершение только процессами, связанными с нодой
      if [[ "$comm" =~ ^(python|python3|bash|sh)$ && "$pcomm" =~ ^(bash|sh|run_rl_swarm.sh)$ ]]; then
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

  echo "[$(date)] Дополнительно убиваем подвисшие процессы..."
  pkill -9 -f "swarm_launcher" 2>/dev/null
  pkill -9 -f "hivemind" 2>/dev/null
  pkill -9 -f "p2pd" 2>/dev/null
  pkill -9 -f "gpu_stats" 2>/dev/null
  pkill -9 -f "torch_shm_manager" 2>/dev/null
  rm -f /tmp/hivemind-p2pd-*.sock 2>/dev/null
}

while true; do
  echo "[$(date)] Запуск Gensyn-ноды..."

  # Удаляем старый лог
  rm -f "$TMP_LOG"

  # Запускаем скрипт с автоответами
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
