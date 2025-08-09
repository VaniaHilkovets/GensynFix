#!/bin/bash
# BlockAssist Official Installer + Firefox
set -e

echo "========================================="
echo "BlockAssist Installer (Official + Firefox)"
echo "========================================="

# Step 1: Clone repo
echo -e "\n[Step 1] Cloning repository..."
cd ~
if [ -d "blockassist" ]; then
    rm -rf blockassist
fi
git clone https://github.com/gensyn-ai/blockassist.git
cd blockassist
PROJECT_DIR=$(pwd)

# Step 2: Install Java
echo -e "\n[Step 2] Installing Java..."
chmod +x setup.sh
./setup.sh

# Step 3: Install pyenv
echo -e "\n[Step 3] Installing pyenv..."
if [ -d "$HOME/.pyenv" ]; then
    rm -rf "$HOME/.pyenv"
fi
curl -fsSL https://pyenv.run | bash

# Add to bashrc
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc

# Activate pyenv for current session
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Step 4: Install Python 3.10
echo -e "\n[Step 4] Installing Python 3.10..."
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
pyenv install 3.10
pyenv global 3.10

# Step 5: Install psutil and readchar
echo -e "\n[Step 5] Installing Python packages..."
pip install psutil readchar

# Install Firefox
echo -e "\n[Extra] Installing Firefox..."
sudo apt install -y firefox

# Create Firefox desktop shortcut
echo -e "\nCreating Firefox shortcut on desktop..."
DESKTOP_DIR="$HOME/Desktop"
if [ ! -d "$DESKTOP_DIR" ]; then
    DESKTOP_DIR="$HOME/Рабочий стол"
fi
if [ ! -d "$DESKTOP_DIR" ]; then
    mkdir -p "$DESKTOP_DIR"
fi

cat > "$DESKTOP_DIR/Firefox.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=Firefox Web Browser
Comment=Browse the World Wide Web
GenericName=Web Browser
Keywords=Internet;WWW;Browser;Web;Explorer
Exec=firefox %u
Terminal=false
X-MultipleArgs=false
Type=Application
Icon=firefox
Categories=GNOME;GTK;Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;application/rss+xml;application/rdf+xml;image/gif;image/jpeg;image/png;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;x-scheme-handler/chrome;video/webm;application/x-xpinstall;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/Firefox.desktop"

# Make it trusted on GNOME
if command -v gio &> /dev/null; then
    gio set "$DESKTOP_DIR/Firefox.desktop" metadata::trusted true 2>/dev/null || true
fi

echo -e "\n========================================="
echo "Installation complete!"
echo ""
echo "✅ Installed:"
echo "  - BlockAssist and all dependencies"
echo "  - Firefox browser"
echo "  - Firefox shortcut on desktop"
echo ""
echo "To run BlockAssist:"
echo "  cd $PROJECT_DIR"
echo "  python run.py"
echo ""
echo "Note: You may need to restart your terminal or run:"
echo "  source ~/.bashrc"
echo "========================================="
