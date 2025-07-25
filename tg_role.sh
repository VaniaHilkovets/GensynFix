#!/usr/bin/env bash
set -euxo pipefail

echo "=== [1/5] Устанавливаем зависимости ==="
apt update
apt install -y wget curl nano

echo "=== [2/5] Устанавливаем Go 1.23.10 ==="
cd /tmp
wget -q https://go.dev/dl/go1.23.10.linux-amd64.tar.gz
rm -rf /usr/local/go
tar -C /usr/local -xzf go1.23.10.linux-amd64.tar.gz

if ! grep -q '/usr/local/go/bin' ~/.bashrc; then
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
fi
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin

echo "Go версия:"
go version

echo "=== [3/5] Устанавливаем GSwarm ==="
go install github.com/Deep-Commit/gswarm/cmd/gswarm@latest

echo "gswarm установлен по пути: $(which gswarm)"

echo "=== [4/5] Проверяем gswarm ==="
gswarm --help || { echo 'Ошибка установки gswarm!'; exit 2; }

echo "=== [5/5] Запускаем мастер настройки (вводите параметры Telegram-бота) ==="
sleep 1
gswarm

echo "=== ✅ Установка завершена! ==="
