#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER — AUTO INSTALLER v3
# =====================================

set -e

BASE="/root/iptv_pro"
BIN="/usr/local/bin/menu"

echo "================================="
echo " IPTV PRO SERVER INSTALLER v3"
echo "================================="

if [ "$EUID" -ne 0 ]; then
  echo "Execute como root:"
  echo "sudo bash install.sh"
  exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."
apt install -y ffmpeg curl wget git python3 python3-pip vnstat

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

# =====================================
# SERVER HLS
# =====================================

start_server() {

if ! pgrep -f "http.server 8080" >/dev/null; then

cd "$HLS"

python3 -m http.server 8080 >/dev/null 2>&1 &

echo "Servidor HLS iniciado na porta 8080"

fi

}

# =====================================
# UTIL
# =====================================

sanitize_name() {

echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'

}

pause(){

echo
read -rp "Pressione ENTER para voltar..."

}

# =====================================
# ADD YOUTUBE
# =====================================

add_youtube(){

clear

read -rp "Nome do canal: " NAME

NAME=$(sanitize_name "$NAME")

read -rp "Link YouTube: " LINK

(

while true; do

URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)

if [ -z "$URL" ]; then
echo "Erro ao obter stream"
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

echo "Stream caiu, reiniciando..."
sleep 3

done

) &

STREAMS["$NAME"]=$!

echo
echo "Canal adicionado!"

pause

}

# =====================================
# LISTAR CANAIS
# =====================================

list_channels(){

while true; do

clear

echo "CANAIS DISPONÍVEIS"
echo "------------------"

for FILE in "$HLS"/*.m3u8; do
[ -f "$FILE" ] || continue
basename "$FILE" .m3u8
done

echo
echo "0) Voltar"

read OP

[ "$OP" = "0" ] && return

done

}

# =====================================
# REMOVER CANAL
# =====================================

remove_channel(){

while true; do

clear

echo "REMOVER CANAL"

read -rp "Nome do canal: " NAME

rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts

echo
echo "Canal removido"

echo
echo "0) Voltar"

read OP

[ "$OP" = "0" ] && return

done

}

# =====================================
# PARAR STREAM
# =====================================

stop_stream(){

read -rp "Nome do canal: " NAME

PID="${STREAMS[$NAME]}"

if [ -n "$PID" ]; then

kill "$PID"

unset STREAMS["$NAME"]

echo "Canal parado"

else

echo "Canal não encontrado"

fi

pause

}

# =====================================
# DASHBOARD
# =====================================

dashboard(){

while true; do

clear

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " DASHBOARD IPTV"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

echo
echo "0) Voltar"

read OP

[ "$OP" = "0" ] && return

done

}

# =====================================
# EXPORT PLAYLIST
# =====================================

export_playlist(){

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

pause

}

# =====================================
# STATUS SERVIDOR
# =====================================

server_status(){

while true; do

clear

echo "STATUS DO SERVIDOR"
echo

top -bn1 | grep Cpu

echo
free -h

echo
df -h /

echo
echo "0) Voltar"

read OP

[ "$OP" = "0" ] && return

done

}

# =====================================
# LINKS STREAM
# =====================================

show_links(){

while true; do

clear

IP=$(hostname -I | awk '{print $1}')

echo "LINKS DOS CANAIS"
echo

for FILE in "$HLS"/*.m3u8; do

[ -f "$FILE" ] || continue

NAME=$(basename "$FILE" .m3u8)

echo "$NAME"
echo "http://$IP:8080/$NAME.m3u8"
echo

done

echo "0) Voltar"

read OP

[ "$OP" = "0" ] && return

done

}

# =====================================
# LIMPAR SEGMENTOS
# =====================================

clean_segments(){

find "$HLS" -name "*.ts" -type f -mmin +10 -delete

echo "Segmentos antigos removidos"

pause

}

# =====================================
# BACKUP
# =====================================

backup(){

tar -czf "$BASE/backup.tar.gz" "$BASE"

echo
echo "Backup criado:"
echo "$BASE/backup.tar.gz"

pause

}

# =====================================
# REINICIAR HLS
# =====================================

restart_hls(){

pkill -f "http.server"

cd "$HLS"

python3 -m http.server 8080 &

echo "Servidor reiniciado"

pause

}

# =====================================
# MENU
# =====================================

menu(){

start_server

while true; do

clear

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IPTV PRO SERVER v3"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1) Adicionar canal YouTube"
echo "2) Parar canal"
echo "3) Dashboard"
echo "4) Exportar playlist"
echo "5) Limpar segmentos"
echo "6) Backup"
echo "7) Listar canais"
echo "8) Remover canal"
echo "9) Status do servidor"
echo "10) Ver links dos canais"
echo "11) Reiniciar servidor HLS"
echo "0) Sair"
echo

read -rp "Opção: " OP

case "$OP" in

1) add_youtube ;;
2) stop_stream ;;
3) dashboard ;;
4) export_playlist ;;
5) clean_segments ;;
6) backup ;;
7) list_channels ;;
8) remove_channel ;;
9) server_status ;;
10) show_links ;;
11) restart_hls ;;
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
