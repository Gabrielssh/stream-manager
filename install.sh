#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER AUTO INSTALL
# =====================================

set -e

BASE="/root/iptv_pro"
HLS="$BASE/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"
MENU="/usr/local/bin/menu"

echo "================================="
echo " IPTV PRO SERVER INSTALL"
echo "================================="

if [ "$EUID" -ne 0 ]; then
echo "Execute como root"
exit 1
fi

echo "[+] Atualizando sistema..."
apt update -y

echo "[+] Instalando dependências..."
apt install -y ffmpeg nginx curl vnstat python3

echo "[+] Instalando yt-dlp..."
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp

chmod +x /usr/local/bin/yt-dlp

echo "[+] Criando estrutura..."

mkdir -p "$HLS"
mkdir -p "$BASE/backup"
mkdir -p "$BASE/logs"

touch "$DB"

# =====================================
# CONFIGURAR NGINX
# =====================================

cat > /etc/nginx/sites-available/iptv <<EOF
server {

listen 8080;

location / {

types {
application/vnd.apple.mpegurl m3u8;
video/mp2t ts;
}

root $HLS;

add_header Cache-Control no-cache;

}

}
EOF

ln -sf /etc/nginx/sites-available/iptv /etc/nginx/sites-enabled/iptv
rm -f /etc/nginx/sites-enabled/default

systemctl restart nginx

# =====================================
# CRIAR MENU IPTV
# =====================================

cat > "$MENU" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="$BASE/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"

declare -A STREAMS

pause(){
read -rp "Pressione ENTER..."
}

sanitize(){
echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'
}

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

sleep 5

done

) &

STREAMS["$NAME"]=$!

}

add_channel(){

clear

read -rp "Nome do canal: " NAME
NAME=$(sanitize "$NAME")

read -rp "Link: " LINK

echo "$NAME|$LINK" >> "$DB"

start_stream "$NAME" "$LINK"

echo "Canal adicionado"

pause

}

stop_channel(){

read -rp "Nome do canal: " NAME

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

activate_channel(){

read -rp "Nome do canal: " NAME

LINK=$(grep "^$NAME|" "$DB" | cut -d "|" -f2)

start_stream "$NAME" "$LINK"

pause

}

activate_all(){

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

list_channels(){

cut -d "|" -f1 "$DB"

pause

}

remove_channel(){

read -rp "Nome do canal: " NAME

sed -i "/^$NAME|/d" "$DB"

rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts

echo "Canal removido"

pause

}

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

export_playlist(){

IP=$(hostname -I | awk '{print $1}')

echo "#EXTM3U" > "$PLAYLIST"

while IFS="|" read -r NAME LINK
do

echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
echo "http://$IP:8080/$NAME.m3u8" >> "$PLAYLIST"

done < "$DB"

echo "Playlist criada"

pause

}

clean_segments(){

find "$HLS" -name "*.ts" -mmin +10 -delete

echo "Segmentos removidos"

pause

}

backup(){

tar -czf "$BASE/backup/iptv_backup.tar.gz" "$BASE"

echo "Backup criado"

pause

}

restart_hls(){

systemctl restart nginx

echo "Servidor reiniciado"

pause

}

show_off(){

for NAME in $(cut -d "|" -f1 "$DB")
do

PID="${STREAMS[$NAME]}"

if ! ps -p "$PID" >/dev/null 2>&1; then
echo "$NAME"
fi

done

pause

}

show_uptime(){

for NAME in "${!STREAMS[@]}"
do

PID="${STREAMS[$NAME]}"

if ps -p "$PID" >/dev/null 2>&1; then

TIME=$(ps -p "$PID" -o etime=)

echo "$NAME | $TIME"

fi

done

pause

}

menu(){

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
echo "8) Ver links"
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
EOF

chmod +x "$MENU"

echo
echo "================================="
echo " INSTALAÇÃO CONCLUÍDA"
echo "================================="
echo
echo "Digite:"
echo
echo "menu"
echo
