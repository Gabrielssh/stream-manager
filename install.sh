#!/usr/bin/env bash

# ==========================================
# STREAM MANAGER PRO ULTRA — INSTALLER
# Instala tudo automático 24/7
# ==========================================

set -e

BIN="/usr/local/bin/menu"
BASE="/root/stream_manager"

echo "======================================"
echo " STREAM MANAGER PRO ULTRA INSTALLER"
echo "======================================"

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."
apt install -y \
  ffmpeg \
  tmux \
  git \
  curl \
  wget \
  coreutils \
  ufw

echo "[+] Instalando yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

echo "[+] Criando diretórios..."
mkdir -p "$BASE/streams"
mkdir -p "$BASE/logs"

echo "[+] Criando script principal..."

cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE_DIR="/root/stream_manager"
STREAM_DIR="$BASE_DIR/streams"
LOG_DIR="$BASE_DIR/logs"
SCHEDULE_FILE="$BASE_DIR/schedule.txt"

mkdir -p "$STREAM_DIR" "$LOG_DIR"
touch "$SCHEDULE_FILE"

declare -A STREAMS_PID

dashboard() {
  while true; do
    clear
    echo "===== STREAM MANAGER ====="
    echo "Streams: ${#STREAMS_PID[@]}"
    uptime
    sleep 2
  done
}

add_stream() {
  read -rp "Nome: " NAME
  read -rp "Link: " LINK
  ffmpeg -re -i "$LINK" -f null - >/dev/null 2>&1 &
  STREAMS_PID["$NAME"]=$!
}

stop_stream() {
  read -rp "Nome: " NAME
  kill "${STREAMS_PID[$NAME]}" 2>/dev/null
  unset STREAMS_PID["$NAME"]
}

backup_system() {
  tar -czf "$BASE_DIR/backup.tar.gz" "$BASE_DIR"
  echo "Backup criado."
}

system_monitor() {
  clear
  top -bn1 | head -15
  read -rp "Pressione ENTER..."
}

run_tmux() {
  tmux new -A -s stream_manager "$0"
}

install_systemd() {
  cat > /etc/systemd/system/stream-manager.service << SYS
[Unit]
Description=Stream Manager
After=network.target

[Service]
ExecStart=/usr/local/bin/menu
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SYS

  systemctl daemon-reload
  systemctl enable stream-manager
  systemctl start stream-manager
  echo "Systemd ativado!"
}

menu() {
  while true; do
    echo
    echo "1) Add stream"
    echo "2) Stop stream"
    echo "3) Dashboard"
    echo "4) Monitor VPS"
    echo "5) Backup"
    echo "6) Tmux 24/7"
    echo "7) Systemd auto boot"
    echo "0) Sair"

    read -rp "Opção: " OP

    case "$OP" in
      1) add_stream ;;
      2) stop_stream ;;
      3) dashboard ;;
      4) system_monitor ;;
      5) backup_system ;;
      6) run_tmux ;;
      7) install_systemd ;;
      0) exit ;;
      *) echo "Opção inválida" ;;
    esac
  done
}

menu
EOF

chmod +x "$BIN"

echo "[+] Configurando firewall..."

ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

echo
echo "======================================"
echo " INSTALAÇÃO CONCLUÍDA ✅"
echo "======================================"
echo
echo "Digite:"
echo "menu"
echo
