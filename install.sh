#!/usr/bin/env bash

set -e

BASE="/root/iptv_pro"
HLS="$BASE/hls"
LOGS="$BASE/logs"
BIN="/usr/local/bin/menu"
COOKIES="$BASE/cookies.txt"

echo "===== IPTV PRO ANTI-BOT INSTALLER ====="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root"
  exit 1
fi

echo "Instalando dependências..."
apt update -y
apt install -y ffmpeg nginx curl wget git python3 nodejs npm

echo "Instalando yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$HLS"
mkdir -p "$LOGS"

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

echo "Criando engine auto-start..."
cat > "$BASE/autostart.sh" << 'EOF'
#!/usr/bin/env bash
BASE="/root/iptv_pro"
LOGS="$BASE/logs"
mkdir -p "$LOGS"

echo "$(date) IPTV engine iniciado" >> "$LOGS/system.log"

while true; do
  sleep 60
done
EOF

chmod +x "$BASE/autostart.sh"

echo "Criando serviço systemd..."
cat > /etc/systemd/system/iptv.service << EOF
[Unit]
Description=IPTV Pro Streaming Engine
After=network.target

[Service]
Type=simple
ExecStart=$BASE/autostart.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iptv
systemctl start iptv

echo "Criando menu..."
cat > "$BIN" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
LOGS="$BASE/logs"
PLAYLIST="$BASE/playlist.m3u"
COOKIES="$BASE/cookies.txt"

declare -A STREAMS

add_channel() {
  read -rp "Nome canal: " NAME
  read -rp "Link YouTube: " LINK

  LOGFILE="$LOGS/$NAME.log"

  (
    while true; do
      # yt-dlp com cookies para evitar bloqueio anti-bot
      URL=$(yt-dlp --cookies "$COOKIES" -f b -g "$LINK" 2>>"$LOGFILE") || {
        echo "$(date) Erro ao extrair URL. Tentando novamente em 10s..." >> "$LOGFILE"
        sleep 10
        continue
      }

      ffmpeg -loglevel error -hide_banner \
      -re -i "$URL" \
      -c copy \
      -f hls \
      -hls_time 4 \
      -hls_list_size 6 \
      "$HLS/$NAME.m3u8" \
      >>"$LOGFILE" 2>&1

      sleep 2
    done
  ) >/dev/null 2>&1 &

  STREAMS["$NAME"]=$!
}

stop_channel() {
  read -rp "Nome: " NAME
  kill "${STREAMS[$NAME]}" 2>/dev/null
  unset STREAMS["$NAME"]
}

export_playlist() {
  IP=$(curl -4 -s ifconfig.me)
  echo "#EXTM3U" > "$PLAYLIST"

  for FILE in "$HLS"/*.m3u8; do
    NAME=$(basename "$FILE" .m3u8)
    echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
    echo "http://$IP/hls/$NAME.m3u8" >> "$PLAYLIST"
  done

  echo
  echo "Playlist completa criada:"
  echo "$PLAYLIST"
  echo "Pode abrir direto no VLC ou IPTV Smarters."
  read
}

dashboard() {
  while true; do
    clear
    echo "===== IPTV PRO DASHBOARD ====="
    echo "Streams ativos: ${#STREAMS[@]}"
    echo

    for NAME in "${!STREAMS[@]}"; do
      PID="${STREAMS[$NAME]}"
      ps -p "$PID" >/dev/null && echo "▶ $NAME ON" || echo "✖ $NAME OFF"
    done

    sleep 2
  done
}

view_logs() {
  read -rp "Nome canal: " NAME
  tail -f "$LOGS/$NAME.log"
}

menu() {
  while true; do
    clear
    echo "===== IPTV PRO ANTI-BOT ====="
    echo "1) Adicionar canal"
    echo "2) Parar canal"
    echo "3) Dashboard"
    echo "4) Exportar playlist"
    echo "5) Ver logs"
    echo "0) Sair"
    echo

    read -rp "Opção: " OP

    case "$OP" in
      1) add_channel ;;
      2) stop_channel ;;
      3) dashboard ;;
      4) export_playlist ;;
      5) view_logs ;;
      0) exit ;;
    esac
  done
}

menu
EOF

chmod +x "$BIN"

echo
echo "===== INSTALAÇÃO CONCLUÍDA ====="
echo "Digite: menu"
echo "Certifique-se de ter exportado cookies do YouTube para $COOKIES"
