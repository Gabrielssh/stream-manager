#!/usr/bin/env bash

# ==========================================
# STREAM MANAGER PRO — AUTO INSTALLER
# ==========================================

set -e

BIN="/usr/local/bin/menu"
BASE="/root/stream_manager"

echo "======================================"
echo " STREAM MANAGER PRO INSTALLER"
echo "======================================"

# ROOT CHECK
if [ "$EUID" -ne 0 ]; then
  echo "Execute como root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."
apt install -y ffmpeg tmux git curl wget coreutils

echo "[+] Instalando yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

echo "[+] Criando diretórios..."
mkdir -p "$BASE/streams"
mkdir -p "$BASE/logs"

echo "[+] Instalando menu principal..."

cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE_DIR="/root/stream_manager"
STREAM_DIR="$BASE_DIR/streams"
LOG_DIR="$BASE_DIR/logs"

mkdir -p "$STREAM_DIR" "$LOG_DIR"

declare -A STREAMS_PID
declare -A STREAM_HISTORY
declare -A STREAM_LINK

# -------------------------
# DASHBOARD
# -------------------------
dashboard() {
  while true; do
    clear
    echo "===== STREAM MANAGER ====="
    echo "Streams ativas: ${#STREAMS_PID[@]}"
    uptime
    echo

    for NAME in "${!STREAMS_PID[@]}"; do
      PID="${STREAMS_PID[$NAME]}"
      if ps -p "$PID" >/dev/null 2>&1; then
        echo "▶ $NAME (PID $PID) ON"
      else
        echo "✖ $NAME OFF"
      fi
    done

    sleep 2
  done
}

# -------------------------
# ADD STREAM
# -------------------------
add_stream() {
  read -rp "Nome do canal: " NAME
  read -rp "Link YouTube/URL: " LINK

  (
    while true; do
      URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)
      ffmpeg -re -i "$URL" -f null - >/dev/null 2>&1
      sleep 2
    done
  ) &

  STREAMS_PID["$NAME"]=$!
  STREAM_HISTORY["$NAME"]="STARTED"
  STREAM_LINK["$NAME"]="$LINK"

  echo "Stream iniciada!"
  sleep 1
}

# -------------------------
# START STREAM
# -------------------------
start_stream() {
  read -rp "Nome: " NAME
  LINK="${STREAM_LINK[$NAME]}"

  if [ -z "$LINK" ]; then
    echo "Stream não encontrada!"
    sleep 1
    return
  fi

  (
    while true; do
      URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)
      ffmpeg -re -i "$URL" -f null - >/dev/null 2>&1
      sleep 2
    done
  ) &

  STREAMS_PID["$NAME"]=$!
  STREAM_HISTORY["$NAME"]="RESTARTED"
}

# -------------------------
# STOP STREAM
# -------------------------
stop_stream() {
  read -rp "Nome: " NAME

  PID="${STREAMS_PID[$NAME]}"

  kill "$PID" 2>/dev/null
  unset STREAMS_PID["$NAME"]

  STREAM_HISTORY["$NAME"]="STOPPED"

  echo "Stream parada!"
  sleep 1
}

# -------------------------
# EXPORT M3U
# -------------------------
export_m3u() {
  M3U="$BASE_DIR/playlist.m3u"

  echo "#EXTM3U" > "$M3U"

  for NAME in "${!STREAM_LINK[@]}"; do
    echo "#EXTINF:-1,$NAME" >> "$M3U"
    echo "${STREAM_LINK[$NAME]}" >> "$M3U"
  done

  echo "Playlist criada: $M3U"
  read -rp "ENTER..."
}

# -------------------------
# HISTÓRICO
# -------------------------
history_streams() {
  echo "===== HISTÓRICO ====="

  for NAME in "${!STREAM_HISTORY[@]}"; do
    echo "$NAME → ${STREAM_HISTORY[$NAME]}"
  done

  read -rp "ENTER..."
}

# -------------------------
# BACKUP
# -------------------------
backup_system() {
  tar -czf "$BASE_DIR/backup.tar.gz" "$BASE_DIR"

  echo "Backup criado:"
  echo "$BASE_DIR/backup.tar.gz"

  read -rp "ENTER..."
}

# -------------------------
# MENU
# -------------------------
menu() {
  while true; do
    clear
    echo "===== STREAM MANAGER ====="
    echo "1) Add stream"
    echo "2) Start stream"
    echo "3) Stop stream"
    echo "4) Dashboard"
    echo "5) Export M3U"
    echo "6) Histórico"
    echo "9) Backup"
    echo "0) Sair"
    echo

    read -rp "Opção: " OP

    case "$OP" in
      1) add_stream ;;
      2) start_stream ;;
      3) stop_stream ;;
      4) dashboard ;;
      5) export_m3u ;;
      6) history_streams ;;
      9) backup_system ;;
      0) exit ;;
      *) echo "Opção inválida"; sleep 1 ;;
    esac
  done
}

menu
EOF

chmod +x "$BIN"

echo
echo "======================================"
echo " INSTALAÇÃO CONCLUÍDA ✅"
echo "======================================"
echo
echo "Digite:"
echo "menu"
echo
