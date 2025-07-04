#!/bin/bash

SCRIPT="./run_rl_swarm.sh"
TMP_LOG="/tmp/rlswarm_stdout.log"

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
  while kill -0 "$PID" 2>/dev/null; do
    sleep 5
    for ERR in "${KEYWORDS[@]}"; do
      if grep -q "$ERR" "$TMP_LOG"; then
        echo "[$(date)] ? Найдено '$ERR'. Перезапуск..."
        kill -9 "$PID" 2>/dev/null
        sleep 3
        continue 2
      fi
    done
  done

  echo "[$(date)] ?? Процесс завершён. Перезапуск через 3 секунды..."
  sleep 3
done
