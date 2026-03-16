#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER ULTRA INSTALL
# =====================================

set -e

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"
MENU="/usr/local/bin/menu"

if [ "$EUID" -ne 0 ]; then
 echo "Execute como root"
 exit 1
fi

apt update -y
apt install -y ffmpeg nginx curl vnstat python3

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$HLS"
mkdir -p "$BASE/backup"
mkdir -p "$BASE/logs"
touch "$DB"

chown -R www-data:www-data /var/www/iptv
chmod -R 755 /var/www/iptv

# ================= NGINX =================

cat > /etc/nginx/sites-available/iptv <<EOF
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    server_name _;
    root /var/www/iptv/hls;

    location / {
        autoindex on;

        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }

        add_header Cache-Control no-cache;
        add_header Access-Control-Allow-Origin *;
    }
}
EOF

ln -sf /etc/nginx/sites-available/iptv /etc/nginx/sites-enabled/iptv
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx
systemctl enable nginx

# ================= MENU =================

cat > "$MENU" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"

pause(){ read -rp "Pressione ENTER..."; }

sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

create_service(){

NAME="$1"
LINK="$2"
SERVICE="/etc/systemd/system/iptv-$NAME.service"

cat > "$SERVICE" <<EOL
[Unit]
Description=IPTV Channel $NAME
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5

ExecStart=/usr/bin/bash -c '
while true
do
URL=\$(/usr/local/bin/yt-dlp -f best -g "$LINK" 2>/dev/null)

if [ -n "\$URL" ]; then
/usr/bin/ffmpeg -loglevel error -re -i "\$URL" \
-c:v copy -c:a aac \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments \
"$HLS/$NAME.m3u8"
fi

sleep 5
done
'

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable iptv-$NAME
systemctl restart iptv-$NAME
}

add_channel(){
clear
read -rp "Nome do canal: " NAME
NAME=$(sanitize "$NAME")
read -rp "Link: " LINK
echo "$NAME|$LINK" >> "$DB"
create_service "$NAME" "$LINK"
echo "Canal iniciado"
pause
}

stop_channel(){
read -rp "Nome do canal: " NAME
systemctl stop iptv-$NAME
pause
}

activate_channel(){
read -rp "Nome do canal: " NAME
systemctl restart iptv-$NAME
pause
}

activate_all(){
while IFS="|" read -r NAME LINK
do
systemctl restart iptv-$NAME
done < "$DB"
pause
}

remove_channel(){
read -rp "Nome do canal: " NAME
systemctl stop iptv-$NAME
systemctl disable iptv-$NAME
rm -f /etc/systemd/system/iptv-$NAME.service
rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts
sed -i "/^$NAME|/d" "$DB"
systemctl daemon-reload
pause
}

list_channels(){
cut -d "|" -f1 "$DB"
pause
}

show_links(){
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
pause
}

clean_segments(){
find "$HLS" -name "*.ts" -mmin +10 -delete
pause
}

backup(){
tar -czf "$BASE/backup/iptv_backup.tar.gz" "$BASE"
pause
}

restart_hls(){
systemctl restart nginx
pause
}

show_off(){
while IFS="|" read -r NAME LINK
do
if ! systemctl is-active --quiet iptv-$NAME; then
echo "$NAME OFF"
fi
done < "$DB"
pause
}

show_uptime(){
while IFS="|" read -r NAME LINK
do
echo "$NAME"
systemctl show iptv-$NAME --property=ActiveEnterTimestamp
echo
done < "$DB"
pause
}

show_viewers(){
for FILE in "$HLS"/*.m3u8
do
[ -f "$FILE" ] || continue
NAME=$(basename "$FILE" .m3u8)
COUNT=$(grep "$NAME" /var/log/nginx/access.log | awk '{print $1}' | sort | uniq | wc -l)
echo "$NAME : $COUNT usuários"
done
pause
}

show_mbps(){
for FILE in "$HLS"/*.m3u8
do
[ -f "$FILE" ] || continue
NAME=$(basename "$FILE" .m3u8)
BYTES=$(grep "$NAME" /var/log/nginx/access.log | awk '{sum+=$10} END {print sum}')
[ -z "$BYTES" ] && BYTES=0
MBPS=$(awk "BEGIN {printf \"%.2f\", ($BYTES*8)/(1024*1024)}")
echo "$NAME : $MBPS Mbps"
done
pause
}

menu(){
while true
do
clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IPTV PRO SERVER ULTRA"
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
echo "12) Ativar canal"
echo "13) Ativar todos canais"
echo "14) Mostrar canais OFF"
echo "15) Tempo online"
echo "16) Usuários assistindo"
echo "17) Consumo Mbps por canal"
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
12) activate_channel ;;
13) activate_all ;;
14) show_off ;;
15) show_uptime ;;
16) show_viewers ;;
17) show_mbps ;;
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
echo "Digite: menu"
echo
