#!/bin/bash

# Проверка на tmux/screen
if [[ -z "${TMUX:-}" && -z "${STY:-}" ]]; then
  echo "[ERROR] Запускай в tmux или screen!"
  exit 1
fi

SCRIPT="./run_rl_swarm.sh"
TMP_LOG="/tmp/rlswarm_stdout.log"
ERROR_LOG="/tmp/rlswarm_error.log"
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

# Redirect stderr to log for debug
exec 2>>"$ERROR_LOG"

# Сторожевой процесс
sleep infinity &
SLEEP_GUARD_PID=$!
trap "kill $SLEEP_GUARD_PID 2>/dev/null || true" EXIT

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)" || true
SWARM_PEM="$SCRIPT_DIR/swarm.pem"

kill_node_procs() {
  echo "[$(date)] Завершаем процессы ноды из папки $SCRIPT_DIR..." | tee -a "$TMP_LOG"

  if [ -f "$SWARM_PEM" ]; then
    echo "[$(date)] Убиваем по swarm.pem..." | tee -a "$TMP_LOG"
    fuser -k "$SWARM_PEM" 2>/dev/null || true
    sleep 1
  fi

  echo "[$(date)] Убиваем по /tmp/hivemind-p2pd-*.sock..." | tee -a "$TMP_LOG"
  fuser -k /tmp/hivemind-p2pd-*.sock 2>/dev/null || true
  sleep 1

  echo "[$(date)] Процессы перед убийством:" | tee -a "$TMP_LOG"
  ps aux | grep -E "python|bash|sh|p2p|daemon|hivemind|p2pd|rl-swarm|genrl|wandb|hydra|swarm_launcher|GensynFix|torch_shm_manager|gpu_stats" | grep -v grep || echo "Нет процессов" | tee -a "$TMP_LOG"

  while read -r pid comm ppid pcomm; do
    if [ -d "/proc/$pid/cwd" ] && [[ "$(readlink -f /proc/$pid/cwd)" == *"$SCRIPT_DIR"* ]]; then
      if [[ "$comm" =~ ^(python|python3|bash|sh|p2p|daemon|hivemind|p2pd|wandb|gpu_stats|torch_shm_manager)$ ]] && [ "$pid" != "$$" ] && [ "$pid" != "$SLEEP_GUARD_PID" ]; then
        echo "[$(date)] Убиваем PID=$pid ($comm) с PPID=$ppid ($pcomm)" | tee -a "$TMP_LOG"
        kill -9 "$pid" 2>/dev/null || true
      else
        echo "[$(date)] Пропускаем PID=$pid ($comm)" | tee -a "$TMP_LOG"
      fi
    fi
  done < <(ps -eo pid,comm,ppid --no-headers | while read pid comm ppid; do
    pcomm=$(ps -p "$ppid" -o comm= 2>/dev/null || echo "unknown")
    echo "$pid $comm $ppid $pcomm"
  done || true)

  echo "[$(date)] Дополнительно убиваем..." | tee -a "$TMP_LOG"
  pkill -9 -f "rl-swarm" 2>/dev/null || true
  pkill -9 -f "hivemind" 2>/dev/null || true
  pkill -9 -f "p2pd" 2>/dev/null || true
  pkill -9 -f "swarm_launcher.py" 2>/dev/null || true
  pkill -9 -f "rgym_exp.runner.swarm_launcher" 2>/dev/null || true
  pkill -9 -f "genrl_swarm.runner.swarm_launcher" 2>/dev/null || true
  pkill -9 -f "wandb-core" 2>/dev/null || true
  pkill -9 -f "gpu_stats" 2>/dev/null || true
  pkill -9 -f "torch_shm_manager" 2>/dev/null || true
  pkill -9 -f "while true; do sleep 1;head -v -n 8 /proc/meminfo" 2>/dev/null || true

  # GPU
  for gpu_pid in $(nvidia-smi --query-compute-apps=pid --format=csv,noheader | sort -u 2>/dev/null || echo ""); do
    echo "[$(date)] Убиваем GPU PID=$gpu_pid" | tee -a "$TMP_LOG"
    kill -9 $gpu_pid 2>/dev/null || true
  done
  python3 -c "import torch; torch.cuda.empty_cache()" 2>/dev/null || true

  rm -f /tmp/hivemind-p2pd-*.sock 2>/dev/null || true
  sleep 5

  echo "[$(date)] Процессы после убийства:" | tee -a "$TMP_LOG"
  ps aux | grep -E "python|bash|sh|p2p|daemon|hivemind|p2pd|rl-swarm|genrl|wandb|hydra|swarm_launcher|GensynFix|torch_shm_manager|gpu_stats" | grep -v grep || echo "Нет процессов" | tee -a "$TMP_LOG"
}

while true; do
  echo "[$(date)] Запуск Gensyn-ноды..." | tee -a "$TMP_LOG"
  rm -f "$TMP_LOG" 2>/dev/null || true

  export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

  ( sleep 1 && printf "n\n\n\n" ) | bash "$SCRIPT" 2>&1 | tee -a "$TMP_LOG" &
  PID=$!

  # Цикл мониторинга с fallback
  while true; do
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "[$(date)] PID $PID мёртв. Перезапуск..." | tee -a "$TMP_LOG"
      kill_node_procs
      break
    fi

    sleep 5

    if [ -f "$TMP_LOG" ]; then
      current_mod=$(stat -c %Y "$TMP_LOG" 2>/dev/null || echo 0)
      now=$(date +%s)
      idle_time=$((now - current_mod))

      if (( idle_time > MAX_IDLE )); then
        echo "[$(date)] Idle >10 мин. Перезапуск..." | tee -a "$TMP_LOG"
        kill -9 "$PID" 2>/dev/null || true
        kill_node_procs
        break
      fi
    fi

    for ERR in "${KEYWORDS[@]}"; do
      if grep -E -q "$ERR" "$TMP_LOG" 2>/dev/null; then
        echo "[$(date)] Ошибка '$ERR'. Перезапуск..." | tee -a "$TMP_LOG"
        kill -9 "$PID" 2>/dev/null || true
        kill_node_procs
        break 2
      fi
    done
  done

  echo "[$(date)] Завершён. Перезапуск через 3 сек..." | tee -a "$TMP_LOG"
  sleep 3
done
