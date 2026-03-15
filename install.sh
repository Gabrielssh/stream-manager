#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER — AUTO INSTALLER v2
# =====================================

set -e

BASE="/root/iptv_pro"
BIN="/usr/local/bin/menu"

echo "================================="
echo " IPTV PRO SERVER INSTALLER v2"
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

  if ! pgrep -f "http.server 8080" >/dev/null; then
    cd "$HLS"
    python3 -m http.server 8080 >/dev/null 2>&1 &
    SERVER_PID=$!
    echo "Servidor HLS iniciado na porta 8080"
  fi

}

sanitize_name() {
  echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'
}

add_youtube() {

  read -rp "Nome do canal: " NAME
  NAME=$(sanitize_name "$NAME")

  if [ -f "$HLS/$NAME.m3u8" ]; then
    echo "Canal já existe."
    read
    return
  fi

  read -rp "Link YouTube: " LINK

  (
    while true; do

      URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)

      if [ -z "$URL" ]; then
        echo "Erro ao obter stream..."
        sleep 5
        continue
      fi

      ffmpeg -re -loglevel warning \
      -i "$URL" \
      -c:v copy \
      -c:a aac \
      -f hls \
      -hls_time 4 \
      -hls_list_size 6 \
      -hls_flags delete_segments \
      "$HLS/$NAME.m3u8"

      echo "Stream caiu... reiniciando"
      sleep 3

    done
  ) &

  STREAMS["$NAME"]=$!

}

stop_stream() {

  read -rp "Nome do canal: " NAME

  PID="${STREAMS[$NAME]}"

  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null
    unset STREAMS["$NAME"]
    echo "Canal parado."
  else
    echo "Canal não encontrado."
  fi

  read

}

restart_stream() {

  read -rp "Nome do canal: " NAME

  PID="${STREAMS[$NAME]}"

  if [ -n "$PID" ]; then
    kill "$PID"
    unset STREAMS["$NAME"]
    echo "Reinicie adicionando novamente."
  fi

  read

}

clean_streams() {

  find "$HLS" -name "*.ts" -type f -mmin +10 -delete
  echo "Segmentos antigos removidos."

  read

}

export_playlist() {

  IP=$(hostname -I | awk '{print $1}')

  echo "#EXTM3U" > "$PLAYLIST"

  for FILE in "$HLS"/*.m3u8; do

    [ -f "$FILE" ] || continue

    NAME=$(basename "$FILE" .m3u8)

    echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
    echo "http://$IP:8080/$NAME.m3u8" >> "$PLAYLIST"

  done

  echo
  echo "Playlist criada:"
  echo "$PLAYLIST"

  read

}

dashboard() {

  while true; do

    clear

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " IPTV PRO SERVER DASHBOARD"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo
    echo "Streams ativas: ${#STREAMS[@]}"
    echo

    for NAME in "${!STREAMS[@]}"; do

      PID="${STREAMS[$NAME]}"

      if ps -p "$PID" >/dev/null 2>&1; then

        TIME=$(ps -p "$PID" -o etime=)

        echo "▶ $NAME ON ($TIME)"

      else

        echo "✖ $NAME OFF"

      fi

    done

    sleep 3

  done

}

backup() {

  tar -czf "$BASE/backup.tar.gz" "$BASE"

  echo "Backup criado:"
  echo "$BASE/backup.tar.gz"

  read

}

menu() {

  start_server

  while true; do

    clear

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " IPTV PRO SERVER v2"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "1) Adicionar canal YouTube"
    echo "2) Parar canal"
    echo "3) Reiniciar canal"
    echo "4) Dashboard"
    echo "5) Exportar playlist"
    echo "6) Limpar segmentos"
    echo "7) Backup"
    echo "0) Sair"
    echo

    read -rp "Opção: " OP

    case "$OP" in
      1) add_youtube ;;
      2) stop_stream ;;
      3) restart_stream ;;
      4) dashboard ;;
      5) export_playlist ;;
      6) clean_streams ;;
      7) backup ;;
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
echo "Digite no terminal:"
echo
echo "menu"
echo
