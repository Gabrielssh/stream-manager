#!/usr/bin/env bash

echo "======================================"
echo " STREAM MANAGER PRO ULTRA INSTALLER"
echo "======================================"

# Verificar root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root: sudo bash install.sh"
  exit 1
fi

echo "✔ Root detectado"

echo "📦 Atualizando sistema..."
apt update -y

echo "📦 Instalando dependências..."
apt install -y \
  ffmpeg \
  yt-dlp \
  tmux \
  curl \
  wget \
  git \
  coreutils

echo "📂 Criando diretórios..."
mkdir -p /opt/stream-manager

echo "⬇ Baixando script principal..."
curl -L https://raw.githubusercontent.com/Gabrielssh/stream-manager/main/stream_manager.sh \
  -o /opt/stream-manager/stream_manager.sh

chmod +x /opt/stream-manager/stream_manager.sh

echo "🔗 Criando comando global 'menu'..."
ln -sf /opt/stream-manager/stream_manager.sh /usr/local/bin/menu

echo
echo "======================================"
echo "✅ INSTALAÇÃO CONCLUÍDA"
echo "Digite: menu"
echo "======================================"
