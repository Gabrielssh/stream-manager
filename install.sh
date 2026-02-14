#!/usr/bin/env bash

==========================================

STREAM MANAGER PRO — AUTO INSTALLER HLS

IPTV Streaming Server 24/7

==========================================

set -e

BIN="/usr/local/bin/menu"
BASE="/root/stream_manager"
HLS_BASE="/var/www/hls"

echo "======================================"
echo " STREAM MANAGER PRO INSTALLER"
echo "======================================"

ROOT CHECK

if [ "$EUID" -ne 0 ]; then
echo "Execute como root:"
echo "sudo bash install.sh"
exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."

apt install -y 
ffmpeg 
tmux 
git 
curl 
wget 
nginx

echo "[+] Instalando yt-dlp..."

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp 
-o /usr/local/bin/yt-dlp

chmod +x /usr/local/bin/yt-dlp

echo "[+] Criando diretórios..."

mkdir -p "$BASE/streams"
mkdir -p "$BASE/logs"
mkdir -p "$HLS_BASE"

echo "[+] Configurando nginx..."

cat > /etc/nginx/sites-enabled/hls << 'NG'
server {
listen 80;
location /hls {
root /var/www;
add_header Cache-Control no-cache;
add_header Access-Control-Allow-Origin *;
types {
application/vnd.apple.mpegurl m3u8;
video/mp2t ts;
}
}
}
NG

systemctl restart nginx

echo "[+] Criando menu principal..."

cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE_DIR="/root/stream_manager"
HLS_BASE="/var/www/hls"

mkdir -p "$BASE_DIR" "$HLS_BASE"

declare -A STREAMS_PID
declare -A STREAM_LINK
declare -A STREAM_HISTORY

stream_engine() {
NAME="$1"
LINK="$2"
HLS_DIR="$HLS_BASE/$NAME"

mkdir -p "$HLS_DIR"

while true; do
URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)

if [ -z "$URL" ]; then
  sleep 5
  continue
fi

ffmpeg -re -i "$URL" \
  -c:v libx264 -preset veryfast -g 48 -sc_threshold 0 \
  -c:a aac -ar 44100 \
  -f hls \
  -hls_time 4 \
  -hls_list_size 6 \
  -hls_flags delete_segments \
  "$HLS_DIR/index.m3u8"

sleep 2

done
}

add_stream() {
read -rp "Nome do canal: " NAME
read -rp "Link YouTube: " LINK

stream_engine "$NAME" "$LINK" &
PID=$!

STREAMS_PID["$NAME"]=$PID
STREAM_LINK["$NAME"]=$LINK
STREAM_HISTORY["$NAME"]="STARTED"

echo "Canal iniciado!"
sleep 1
}

start_stream() {
read -rp "Nome: " NAME

LINK="${STREAM_LINK[$NAME]}"

if [ -z "$LINK" ]; then
echo "Canal não encontrado!"
sleep 1
return
fi

stream_engine "$NAME" "$LINK" &
STREAMS_PID["$NAME"]=$!
STREAM_HISTORY["$NAME"]="RESTARTED"
}

stop_stream() {
read -rp "Nome: " NAME

PID="${STREAMS_PID[$NAME]}"

kill "$PID" 2>/dev/null
unset STREAMS_PID["$NAME"]

STREAM_HISTORY["$NAME"]="STOPPED"
}

dashboard() {
while true; do
clear
echo "===== STREAM MANAGER DASHBOARD ====="
uptime
echo

for NAME in "${!STREAMS_PID[@]}"; do
  PID="${STREAMS_PID[$NAME]}"
  if ps -p "$PID" >/dev/null; then
    echo "▶ $NAME ONLINE"
  else
    echo "✖ $NAME OFFLINE"
  fi
done

sleep 2

done
}

export_m3u() {
SERVER_IP=$(hostname -I | awk '{print $1}')
M3U="$BASE_DIR/playlist.m3u"

echo "#EXTM3U" > "$M3U"

for NAME in "${!STREAM_LINK[@]}"; do
echo "#EXTINF:-1,$NAME" >> "$M3U"
echo "http://$SERVER_IP/hls/$NAME/index.m3u8" >> "$M3U"
done

echo "Playlist criada:"
echo "$M3U"
read -rp "ENTER..."
}

history_streams() {
clear
echo "===== HISTÓRICO ====="

for NAME in "${!STREAM_HISTORY[@]}"; do
echo "$NAME → ${STREAM_HISTORY[$NAME]}"
done

read -rp "ENTER..."
}

backup_system() {
tar -czf "$BASE_DIR/backup.tar.gz" "$BASE_DIR"
echo "Backup criado em:"
echo "$BASE_DIR/backup.tar.gz"
read -rp "ENTER..."
}

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
