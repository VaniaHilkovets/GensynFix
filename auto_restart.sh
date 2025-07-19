#!/bin/bash
set -euo pipefail

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

# Сторожевой процесс, чтобы tmux не закрывался
sleep infinity &
SLEEP_GUARD_PID=$!
trap "kill $SLEEP_GUARD_PID 2>/dev/null" EXIT

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
SWARM_PEM="$SCRIPT_DIR/swarm.pem"

kill_node_procs() {
  echo "[$(date)] Завершаем процессы ноды из папки $SCRIPT_DIR..."

  # Убийство по файлу swarm.pem
  if [ -f "$SWARM_PEM" ]; then
    echo "[$(date)] Убиваем процессы, использующие $SWARM_PEM..."
    fuser -k "$SWARM_PEM" 2>/dev/null
    sleep 1
  fi

  # Убийство по сокетам hivemind (чтобы добить все инстансы p2pd)
  echo "[$(date)] Убиваем процессы на сокетах /tmp/hivemind-p2pd-*.sock..."
  fuser -k /tmp/hivemind-p2pd-*.sock 2>/dev/null
  sleep 1

  # Лог процессов перед убийством (для дебага)
  echo "[$(date)] Текущие релевантные процессы перед убийством:"
  ps aux | grep -E "python|bash|sh|p2p|daemon|hivemind|p2pd|rl-swarm|genrl|wandb|hydra|swarm_launcher|GensynFix|torch_shm_manager|gpu_stats" | grep -v grep || echo "Нет процессов"

  # Цикл по cwd (расширен на поддир и новые comm)
  while read -r pid comm ppid pcomm; do
    if [ -d "/proc/$pid/cwd" ] && [[ "$(readlink -f /proc/$pid/cwd)" == *"$SCRIPT_DIR"* ]]; then
      if [[ "$comm" =~ ^(python|python3|bash|sh|p2p|daemon|hivemind|p2pd|wandb|gpu_stats|torch_shm_manager)$ ]]; then
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

  # Расширенный pkill по паттернам из diff (точные аргументы)
  pkill -9 -f "rl-swarm" 2>/dev/null
  pkill -9 -f "hivemind" 2>/dev/null
  pkill -9 -f "p2pd" 2>/dev/null  # Ловит все p2pd
  pkill -9 -f "swarm_launcher.py" 2>/dev/null  # Лаунчер
  pkill -9 -f "rgym_exp.runner.swarm_launcher" 2>/dev/null  # Новый лаунчер
  pkill -9 -f "genrl_swarm.runner.swarm_launcher" 2>/dev/null  # Старый лаунчер
  pkill -9 -f "wandb-core" 2>/dev/null
  pkill -9 -f "gpu_stats" 2>/dev/null
  pkill -9 -f "torch_shm_manager" 2>/dev/null
  pkill -9 -f "while true; do sleep 1;head -v -n 8 /proc/meminfo" 2>/dev/null  # Мониторинг-баш
  sleep 2

  # Лог после убийства
  echo "[$(date)] Процессы после убийства:"
  ps aux | grep -E "python|bash|sh|p2p|daemon|hivemind|p2pd|rl-swarm|genrl|wandb|hydra|swarm_launcher|GensynFix|torch_shm_manager|gpu_stats" | grep -v grep || echo "Нет активных процессов"

  # Очистка сокетов перед перезапуском
  rm -f /tmp/hivemind-p2pd-*.sock 2>/dev/null
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
      if grep -E -q "$ERR" "$TMP_LOG"; then
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
