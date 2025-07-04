#!/bin/bash

SCRIPT="./run_rl_swarm.sh"
TMP_LOG="/tmp/rlswarm_stdout.log"
MAX_IDLE=600  # 10 минут в секундах

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

while true; do
  echo "[$(date)] ?? Запуск Gensyn-ноды..."

  # Удалим старый лог
  rm -f "$TMP_LOG"

  # Запускаем скрипт с автоответами на вопросы
  ( sleep 1 && printf "n\n\n\n" ) | bash "$SCRIPT" 2>&1 | tee "$TMP_LOG" &
  PID=$!

  # Следим за логом и ошибками
  last_mod=$(date +%s)
  while kill -0 "$PID" 2>/dev/null; do
    sleep 5

    # Проверяем обновление лога
    if [ -f "$TMP_LOG" ]; then
      current_mod=$(stat -c %Y "$TMP_LOG")
      now=$(date +%s)
      idle_time=$((now - current_mod))

      if (( idle_time > MAX_IDLE )); then
        echo "[$(date)] ⚠️ Лог не обновлялся более $((MAX_IDLE/60)) минут. Перезапуск ноды..."
        kill -9 "$PID" 2>/dev/null
        sleep 3
        break
      fi
    fi

    # Проверяем ключевые ошибки
    for ERR in "${KEYWORDS[@]}"; do
      if grep -q "$ERR" "$TMP_LOG"; then
        echo "[$(date)] ? Найдено '$ERR'. Перезапуск..."
        kill -9 "$PID" 2>/dev/null
        sleep 3
        break 2
      fi
    done
  done

  echo "[$(date)] ?? Процесс завершён. Перезапуск через 3 секунды..."
  sleep 3
done
