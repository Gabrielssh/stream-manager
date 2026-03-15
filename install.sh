#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER — AUTO INSTALLER
# =====================================

set -e

BASE="/root/iptv_pro"
BIN="/usr/local/bin/menu"

echo "================================="
echo " IPTV PRO SERVER INSTALLER"
echo "================================="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."
apt install -y ffmpeg curl wget git python3 python3-pip

echo "[+] Instalando yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$BASE/hls"

echo "[+] Criando menu IPTV..."

cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
PLAYLIST="$BASE/playlist.m3u"

mkdir -p "$HLS"

declare -A STREAMS

start_server() {
  cd "$HLS"
  python3 -m http.server 8080 >/dev/null 2>&1 &
  SERVER_PID=$!
}

add_youtube() {
  read -rp "Nome do canal: " NAME
  read -rp "Link YouTube: " LINK

  (
    while true; do
      URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)
      [ -z "$URL" ] && sleep 5 && continue

      ffmpeg -re -i "$URL" \
      -c copy \
      -f hls \
      -hls_time 4 \
      -hls_list_size 6 \
      "$HLS/$NAME.m3u8"

      sleep 2
    done
  ) &

  STREAMS["$NAME"]=$!
}

stop_stream() {
  read -rp "Nome: " NAME
  kill "${STREAMS[$NAME]}" 2>/dev/null
  unset STREAMS["$NAME"]
}

export_playlist() {
  IP=$(curl -s ifconfig.me)

  echo "#EXTM3U" > "$PLAYLIST"

  for FILE in "$HLS"/*.m3u8; do
    [ -f "$FILE" ] || continue
    NAME=$(basename "$FILE" .m3u8)

    echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
    echo "http://$IP:8080/$NAME.m3u8" >> "$PLAYLIST"
  done

  echo "Playlist criada:"
  echo "$PLAYLIST"
  read -rp "ENTER..."
}

dashboard() {
  while true; do
    clear
    echo "===== IPTV PRO DASHBOARD ====="
    echo "Streams ativas: ${#STREAMS[@]}"
    echo

    for NAME in "${!STREAMS[@]}"; do
      PID="${STREAMS[$NAME]}"
      if ps -p "$PID" >/dev/null 2>&1; then
        echo "▶ $NAME ON"
      else
        echo "✖ $NAME OFF"
      fi
    done

    sleep 2
  done
}

backup() {
  tar -czf "$BASE/backup.tar.gz" "$BASE"
  echo "Backup criado em $BASE/backup.tar.gz"
  read
}

menu() {
  start_server

  while true; do
    clear
    echo "===== IPTV PRO SERVER ====="
    echo "1) Adicionar canal YouTube"
    echo "2) Parar canal"
    echo "3) Dashboard"
    echo "4) Exportar playlist"
    echo "5) Backup"
    echo "0) Sair"
    echo

    read -rp "Opção: " OP

    case "$OP" in
      1) add_youtube ;;
      2) stop_stream ;;
      3) dashboard ;;
      4) export_playlist ;;
      5) backup ;;
      0) exit ;;
    esac
  done
}

menu
EOF

chmod +x "$BIN"

echo
echo "================================="
echo " INSTALAÇÃO CONCLUÍDA ✅"
echo "================================="
echo
echo "Digite: menu"
echo
