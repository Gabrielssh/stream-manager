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

start_server(){

if ! pgrep -f "http.server 8080" >/dev/null; then
cd "$HLS"
python3 -m http.server 8080 >/dev/null 2>&1 &
echo "Servidor HLS iniciado na porta 8080"
fi

}

pause(){
echo
read -rp "Pressione ENTER para voltar..."
}

sanitize_name(){
echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'
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
sleep 5
continue
fi

ffmpeg -loglevel error -re \
-i "$URL" \
-c:v copy \
-c:a aac \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments \
"$HLS/$NAME.m3u8" >/dev/null 2>&1

sleep 3

done

) &

STREAMS["$NAME"]=$!

echo
echo "Canal adicionado!"

pause

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
# LISTAR CANAIS
# =====================================

list_channels(){

clear
echo "CANAIS DISPONÍVEIS"
echo "------------------"

for FILE in "$HLS"/*.m3u8; do
[ -f "$FILE" ] || continue
basename "$FILE" .m3u8
done

pause

}

# =====================================
# REMOVER CANAL
# =====================================

remove_channel(){

clear
read -rp "Nome do canal: " NAME

rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts

echo "Canal removido"

pause

}

# =====================================
# ATIVAR CANAL
# =====================================

activate_channel(){

clear
echo "ATIVAR CANAL"
echo
echo "Digite 0 para voltar"
echo

read -rp "Nome do canal: " NAME

[ "$NAME" = "0" ] && return

FILE="$HLS/$NAME.m3u8"

if [ ! -f "$FILE" ]; then
echo "Canal não existe"
pause
return
fi

PID="${STREAMS[$NAME]}"

if [ -n "$PID" ] && ps -p "$PID" >/dev/null 2>&1; then
echo "Canal já está ativo"
pause
return
fi

(
while true; do

ffmpeg -loglevel error -re \
-stream_loop -1 \
-i "$FILE" \
-c copy \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments \
"$HLS/$NAME.m3u8" >/dev/null 2>&1

sleep 3

done
) &

STREAMS["$NAME"]=$!

pause

}

# =====================================
# ATIVAR TODOS
# =====================================

activate_all(){

clear
echo "ATIVAR TODOS CANAIS"
echo
echo "1) Confirmar"
echo "0) Voltar"
echo

read -rp "Opção: " OP

[ "$OP" = "0" ] && return

for FILE in "$HLS"/*.m3u8; do

[ -f "$FILE" ] || continue

NAME=$(basename "$FILE" .m3u8)

PID="${STREAMS[$NAME]}"

if [ -z "$PID" ] || ! ps -p "$PID" >/dev/null 2>&1; then

(
while true; do

ffmpeg -loglevel error -re \
-stream_loop -1 \
-i "$FILE" \
-c copy \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments \
"$HLS/$NAME.m3u8" >/dev/null 2>&1

sleep 3

done
) &

STREAMS["$NAME"]=$!

fi

done

pause

}

# =====================================
# CANAIS OFF
# =====================================

show_off_channels(){

clear
echo "CANAIS OFF"
echo "-----------"

for NAME in "${!STREAMS[@]}"; do

PID="${STREAMS[$NAME]}"

if ! ps -p "$PID" >/dev/null 2>&1; then
echo "$NAME"
fi

done

pause

}

# =====================================
# TEMPO ONLINE
# =====================================

show_uptime(){

clear
echo "TEMPO ONLINE DOS CANAIS"
echo "-----------------------"

for NAME in "${!STREAMS[@]}"; do

PID="${STREAMS[$NAME]}"

if ps -p "$PID" >/dev/null 2>&1; then
TIME=$(ps -p "$PID" -o etime=)
echo "▶ $NAME | ONLINE | $TIME"
else
echo "✖ $NAME | OFFLINE"
fi

done

pause

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
echo "Backup criado em $BASE/backup.tar.gz"
pause

}

# =====================================
# REINICIAR HLS
# =====================================

restart_hls(){

pkill -f "http.server"

cd "$HLS"
python3 -m http.server 8080 >/dev/null 2>&1 &

echo "Servidor reiniciado"

pause

}

# =====================================
# LINKS DOS CANAIS
# =====================================

show_links(){

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

pause

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

echo "Playlist criada em $PLAYLIST"

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
echo " IPTV PRO SERVER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1) Adicionar canal YouTube"
echo "2) Parar canal"
echo "3) Exportar playlist"
echo "4) Limpar segmentos"
echo "5) Backup"
echo "6) Listar canais"
echo "7) Remover canal"
echo "8) Ver links dos canais"
echo "9) Reiniciar servidor HLS"
echo "10) Monitor RAM"
echo "11) Monitor Internet"
echo "12) Ativar canal"
echo "13) Ativar todos canais"
echo "14) Mostrar canais OFF"
echo "15) Tempo online dos canais"
echo "0) Sair"
echo

read -rp "Opção: " OP

case "$OP" in

1) add_youtube ;;
2) stop_stream ;;
3) export_playlist ;;
4) clean_segments ;;
5) backup ;;
6) list_channels ;;
7) remove_channel ;;
8) show_links ;;
9) restart_hls ;;
10) free -h ; pause ;;
11) vnstat ; pause ;;
12) activate_channel ;;
13) activate_all ;;
14) show_off_channels ;;
15) show_uptime ;;
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
