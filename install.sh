#!/usr/bin/env bash

==========================================

STREAM MANAGER AUTO INSTALLER

GitHub: https://github.com/Gabrielssh/stream-manager

==========================================

set -e

REPO_URL="https://github.com/Gabrielssh/stream-manager.git"
INSTALL_DIR="/opt/stream-manager"
BIN_PATH="/usr/local/bin/menu"

echo "======================================"
echo "  STREAM MANAGER INSTALLER"
echo "======================================"

-------------------------

Verificar root

-------------------------

if [ "$EUID" -ne 0 ]; then
echo "Execute como root:"
echo "sudo bash install.sh"
exit 1
fi

-------------------------

Atualizar sistema

-------------------------

echo "[+] Atualizando sistema..."
apt update -y
apt upgrade -y

-------------------------

Instalar dependências

-------------------------

echo "[+] Instalando dependências..."

apt install -y 
ffmpeg 
tmux 
git 
curl 
wget 
coreutils

-------------------------

Instalar yt-dlp

-------------------------

echo "[+] Instalando yt-dlp..."

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp 
-o /usr/local/bin/yt-dlp

chmod +x /usr/local/bin/yt-dlp

-------------------------

Clonar repositório

-------------------------

echo "[+] Clonando Stream Manager..."

rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"

-------------------------

Instalar comando menu

-------------------------

echo "[+] Instalando comando global 'menu'..."

cp "$INSTALL_DIR/menu" "$BIN_PATH"
chmod +x "$BIN_PATH"

-------------------------

Criar diretórios padrão

-------------------------

echo "[+] Criando diretórios..."

mkdir -p /root/stream_manager/streams
mkdir -p /root/stream_manager/logs

-------------------------

Finalização

-------------------------

echo
echo "======================================"
echo " INSTALAÇÃO CONCLUÍDA ✅"
echo "======================================"
echo
echo "Digite no terminal:"
echo
echo "menu"
echo
echo "para abrir o Stream Manager."
echo
