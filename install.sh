#!/usr/bin/env bash

set -e

BASE="/root/iptv_pro"
HLS="$BASE/hls"
BIN="/usr/local/bin/menu"

echo "===== IPTV PRO UPGRADE INSTALLER ====="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root"
  exit 1
fi

apt update -y
apt install -y ffmpeg nginx curl wget git python3

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$HLS"

echo "Configurando nginx..."

cat > /etc/nginx/sites-enabled/default << EOF
server {
    listen 80;

    location /hls {
        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }

        root $BASE;
        add_header Cache-Control no-cache;
    }
}
EOF

systemctl restart nginx

echo "Criando menu..."

cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
PLAYLIST="$BASE/playlist.m3u"

declare -A STREAMS

add_channel() {
  read -rp "Nome canal: " NAME
  read -rp "Link YouTube: " LINK

  (
    while true; do
      URL=$(yt-dlp -f best -g "$LINK")
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

stop_channel() {
  read -rp "Nome: " NAME
  kill "${STREAMS[$NAME]}" 2>/dev/null
  unset STREAMS["$NAME"]
}

export_playlist() {
  IP=$(curl -s ifconfig.me)

  echo "#EXTM3U" > "$PLAYLIST"

  for FILE in "$HLS"/*.m3u8; do
    NAME=$(basename "$FILE" .m3u8)
    echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
    echo "http://$IP/hls/$NAME.m3u8" >> "$PLAYLIST"
  done

  echo "Playlist criada:"
  echo "$PLAYLIST"
  read
}

dashboard() {
  while true; do
    clear
    echo "===== IPTV PRO DASHBOARD ====="
    echo "Streams: ${#STREAMS[@]}"

    for NAME in "${!STREAMS[@]}"; do
      PID="${STREAMS[$NAME]}"
      ps -p "$PID" >/dev/null && echo "▶ $NAME ON" || echo "✖ $NAME OFF"
    done

    sleep 2
  done
}

menu() {
  while true; do
    clear
    echo "===== IPTV PRO ====="
    echo "1) Adicionar canal"
    echo "2) Parar canal"
    echo "3) Dashboard"
    echo "4) Exportar playlist"
    echo "0) Sair"
    echo

    read -rp "Opção: " OP

    case "$OP" in
      1) add_channel ;;
      2) stop_channel ;;
      3) dashboard ;;
      4) export_playlist ;;
      0) exit ;;
    esac
  done
}

menu
EOF

chmod +x "$BIN"

echo "Instalação concluída!"
echo "Digite: menu"
