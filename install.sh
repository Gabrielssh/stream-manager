#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
PLAYLIST="$BASE/playlist.m3u"

mkdir -p "$HLS"

declare -A STREAMS

start_server(){

if ! pgrep -f "http.server 8080" >/dev/null; then

cd "$HLS"
python3 -m http.server 8080 >/dev/null 2>&1 &

fi

}

pause(){
echo
read -rp "Pressione ENTER para voltar..."
}

sanitize_name(){
echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'
}

# ==============================
# ADD YOUTUBE
# ==============================

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
echo "Canal iniciado!"

pause

}

# ==============================
# PARAR CANAL
# ==============================

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

# ==============================
# REINICIAR CANAL
# ==============================

restart_stream(){

read -rp "Nome do canal: " NAME

PID="${STREAMS[$NAME]}"

if [ -n "$PID" ]; then
kill "$PID"
unset STREAMS["$NAME"]
echo "Reinicie adicionando novamente"
else
echo "Canal não encontrado"
fi

pause

}

# ==============================
# LISTAR CANAIS
# ==============================

list_channels(){

clear

echo "CANAIS DISPONÍVEIS"
echo

for FILE in "$HLS"/*.m3u8; do
[ -f "$FILE" ] || continue
basename "$FILE" .m3u8
done

pause

}

# ==============================
# REMOVER CANAL
# ==============================

remove_channel(){

read -rp "Nome do canal: " NAME

rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts

echo "Canal removido"

pause

}

# ==============================
# REINICIAR TODOS STREAMS
# ==============================

restart_all(){

pkill ffmpeg

echo "Todos streams foram reiniciados"

pause

}

# ==============================
# EXPORT PLAYLIST
# ==============================

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

# ==============================
# LINKS DOS CANAIS
# ==============================

show_links(){

clear

IP=$(hostname -I | awk '{print $1}')

for FILE in "$HLS"/*.m3u8; do

[ -f "$FILE" ] || continue

NAME=$(basename "$FILE" .m3u8)

echo "$NAME"
echo "http://$IP:8080/$NAME.m3u8"
echo

done

pause

}

# ==============================
# DASHBOARD
# ==============================

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

# ==============================
# STATUS SERVIDOR
# ==============================

server_status(){

clear

top -bn1 | grep Cpu
echo
free -h
echo
df -h /

pause

}

# ==============================
# MONITOR REDE
# ==============================

network_monitor(){

vnstat -l

}

# ==============================
# REINICIAR HLS
# ==============================

restart_hls(){

pkill -f http.server

cd "$HLS"
python3 -m http.server 8080 &

echo "Servidor reiniciado"

pause

}

# ==============================
# LIMPAR SEGMENTOS
# ==============================

clean_segments(){

find "$HLS" -name "*.ts" -type f -mmin +10 -delete

echo "Segmentos antigos removidos"

pause

}

# ==============================
# LIMPEZA TOTAL
# ==============================

clean_all(){

rm -f "$HLS"/*.ts
rm -f "$HLS"/*.m3u8

echo "Todos arquivos HLS removidos"

pause

}

# ==============================
# BACKUP
# ==============================

backup(){

tar -czf "$BASE/backup.tar.gz" "$BASE"

echo "Backup criado em:"
echo "$BASE/backup.tar.gz"

pause

}

# ==============================
# MENU
# ==============================

menu(){

start_server

while true; do

clear

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "        IPTV PRO SERVER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "STREAMS"
echo "1) Adicionar canal YouTube"
echo "2) Parar canal"
echo "3) Reiniciar canal"
echo "4) Listar canais"
echo "5) Remover canal"
echo "6) Reiniciar todos streams"
echo
echo "PLAYLIST"
echo "7) Exportar playlist"
echo "8) Ver links dos canais"
echo
echo "SERVIDOR"
echo "9) Dashboard"
echo "10) Status do servidor"
echo "11) Monitor de rede"
echo "12) Reiniciar servidor HLS"
echo
echo "MANUTENÇÃO"
echo "13) Limpar segmentos"
echo "14) Limpeza completa HLS"
echo "15) Backup"
echo
echo "0) Sair"
echo

read -rp "Opção: " OP

case "$OP" in

1) add_youtube ;;
2) stop_stream ;;
3) restart_stream ;;
4) list_channels ;;
5) remove_channel ;;
6) restart_all ;;
7) export_playlist ;;
8) show_links ;;
9) dashboard ;;
10) server_status ;;
11) network_monitor ;;
12) restart_hls ;;
13) clean_segments ;;
14) clean_all ;;
15) backup ;;
0) exit ;;

esac

done

}

menu
