#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"

mkdir -p "$HLS"
touch "$DB"

declare -A STREAMS

pause(){
echo
read -rp "Pressione ENTER para voltar..."
}

sanitize(){
echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'
}

# =====================================
# SERVIDOR HLS
# =====================================

start_server(){

if ! pgrep -f "http.server 8080" >/dev/null; then
cd "$HLS"
python3 -m http.server 8080 >/dev/null 2>&1 &
echo "Servidor HLS iniciado porta 8080"
fi

}

# =====================================
# INICIAR STREAM
# =====================================

start_stream(){

NAME="$1"
LINK="$2"

(

while true
do

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

}

# =====================================
# ADICIONAR CANAL
# =====================================

add_channel(){

clear

read -rp "Nome do canal: " NAME
NAME=$(sanitize "$NAME")

read -rp "Link YouTube: " LINK

echo "$NAME|$LINK" >> "$DB"

start_stream "$NAME" "$LINK"

echo
echo "Canal adicionado!"

pause

}

# =====================================
# PARAR CANAL
# =====================================

stop_channel(){

echo "Digite 0 para voltar"
read -rp "Nome do canal: " NAME

[ "$NAME" = "0" ] && return

PID="${STREAMS[$NAME]}"

if [ -n "$PID" ]; then
kill "$PID"
unset STREAMS["$NAME"]
echo "Canal parado"
else
echo "Canal não ativo"
fi

pause

}

# =====================================
# ATIVAR CANAL
# =====================================

activate_channel(){

echo "Digite 0 para voltar"
read -rp "Nome do canal: " NAME

[ "$NAME" = "0" ] && return

LINK=$(grep "^$NAME|" "$DB" | cut -d "|" -f2)

if [ -z "$LINK" ]; then
echo "Canal não encontrado"
pause
return
fi

PID="${STREAMS[$NAME]}"

if ps -p "$PID" >/dev/null 2>&1; then
echo "Canal já ativo"
pause
return
fi

start_stream "$NAME" "$LINK"

echo "Canal ativado"

pause

}

# =====================================
# ATIVAR TODOS CANAIS
# =====================================

activate_all(){

clear

echo "1) Confirmar"
echo "0) Voltar"
echo

read -rp "Opção: " OP

[ "$OP" = "0" ] && return

while IFS="|" read -r NAME LINK
do

PID="${STREAMS[$NAME]}"

if ! ps -p "$PID" >/dev/null 2>&1; then
echo "Iniciando $NAME"
start_stream "$NAME" "$LINK"
fi

done < "$DB"

pause

}

# =====================================
# LISTAR CANAIS
# =====================================

list_channels(){

clear

echo "CANAIS"
echo "------"

cut -d "|" -f1 "$DB"

pause

}

# =====================================
# REMOVER CANAL
# =====================================

remove_channel(){

read -rp "Nome do canal: " NAME

sed -i "/^$NAME|/d" "$DB"

rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts

echo "Canal removido"

pause

}

# =====================================
# LINKS DOS CANAIS
# =====================================

show_links(){

clear

IP=$(hostname -I | awk '{print $1}')

while IFS="|" read -r NAME LINK
do

echo "$NAME"
echo "http://$IP:8080/$NAME.m3u8"
echo

done < "$DB"

pause

}

# =====================================
# PLAYLIST
# =====================================

export_playlist(){

IP=$(hostname -I | awk '{print $1}')

echo "#EXTM3U" > "$PLAYLIST"

while IFS="|" read -r NAME LINK
do

echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
echo "http://$IP:8080/$NAME.m3u8" >> "$PLAYLIST"

done < "$DB"

echo "Playlist criada:"
echo "$PLAYLIST"

pause

}

# =====================================
# CANAIS OFF
# =====================================

show_off(){

clear

echo "CANAIS OFF"
echo

while IFS="|" read -r NAME LINK
do

PID="${STREAMS[$NAME]}"

if ! ps -p "$PID" >/dev/null 2>&1; then
echo "$NAME"
fi

done < "$DB"

pause

}

# =====================================
# TEMPO ONLINE
# =====================================

show_uptime(){

clear

echo "TEMPO ONLINE"
echo

for NAME in "${!STREAMS[@]}"
do

PID="${STREAMS[$NAME]}"

if ps -p "$PID" >/dev/null 2>&1; then

TIME=$(ps -p "$PID" -o etime=)

echo "$NAME | ONLINE | $TIME"

else

echo "$NAME | OFFLINE"

fi

done

pause

}

# =====================================
# LIMPAR SEGMENTOS
# =====================================

clean_segments(){

find "$HLS" -name "*.ts" -mmin +10 -delete

echo "Segmentos removidos"

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

pkill -f http.server

cd "$HLS"
python3 -m http.server 8080 >/dev/null 2>&1 &

echo "Servidor reiniciado"

pause

}

# =====================================
# MENU
# =====================================

menu(){

start_server

while true
do

clear

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IPTV PRO SERVER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1) Adicionar canal"
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
echo "15) Tempo online canais"
echo "0) Sair"
echo

read -rp "Opção: " OP

case "$OP" in

1) add_channel ;;
2) stop_channel ;;
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
14) show_off ;;
15) show_uptime ;;
0) exit ;;

esac

done

}

menu
