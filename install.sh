#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER INSTALL + MENU (FIX)
# QUALIDADE ORIGINAL PRESERVADA
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
apt install -y ffmpeg nginx curl vnstat python3 glances

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
BACKUP_DIR="$BASE/backup"

pause(){ read -rp "Pressione ENTER..."; }

sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

normalize_link(){
    echo "$1" | sed 's#m.youtube.com#www.youtube.com#g' | cut -d "&" -f1
}

# ================= QUALIDADE (FIX REAL) =================
select_quality(){
    echo
    echo "Escolher qualidade:"
    echo "1) 360p"
    echo "2) 480p"
    echo "3) 720p"
    echo "4) 1080p"
    echo "5) Melhor disponível"
    echo

    read -rp "Opção: " Q

    case "$Q" in
        1) QUALITY='bv*[height<=360]+ba/b[height<=360]' ;;
        2) QUALITY='bv*[height<=480]+ba/b[height<=480]' ;;
        3) QUALITY='bv*[height<=720]+ba/b[height<=720]' ;;
        4) QUALITY='bv*[height<=1080]+ba/b[height<=1080]' ;;
        5) QUALITY='bv*+ba/b' ;;
        *) QUALITY='bv*+ba/b' ;;
    esac
}

# ================= CRIA CANAL =================
create_service(){

    NAME="$1"
    LINK="$2"
    QUALITY="$3"

    SCRIPT="/root/iptv_pro/run-$NAME.sh"
    SERVICE="/etc/systemd/system/iptv-$NAME.service"

    cat > "$SCRIPT" <<EOF2
#!/usr/bin/env bash

HLS="/var/www/iptv/hls"

while true
do
URL=\$(/usr/local/bin/yt-dlp --no-playlist -f "$QUALITY" -g "$LINK" 2>/dev/null)

if [ -z "\$URL" ]; then
    sleep 5
    continue
fi

/usr/bin/ffmpeg -loglevel error -re -i "\$URL" \
-c copy \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments+append_list+independent_segments \
-hls_segment_type mpegts \
"\$HLS/$NAME.m3u8"

sleep 5
done
EOF2

    chmod +x "$SCRIPT"

    cat > "$SERVICE" <<EOF2
[Unit]
Description=IPTV Channel $NAME
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF2

    systemctl daemon-reload
    systemctl enable iptv-$NAME
    systemctl restart iptv-$NAME
}

add_channel(){
    clear
    read -rp "Nome do canal: " NAME
    NAME=$(sanitize "$NAME")

    read -rp "Link: " LINK
    LINK=$(normalize_link "$LINK")

    select_quality

    echo "$NAME|$LINK|$QUALITY" >> "$DB"

    create_service "$NAME" "$LINK" "$QUALITY"

    echo "Canal iniciado com qualidade preservada!"
    pause
}

# ================= RESTO DO MENU (SEM ALTERAÇÃO FUNCIONAL) =================

list_channels(){ cut -d "|" -f1 "$DB"; pause; }

stop_channel(){ read -rp "Nome: " N; systemctl stop iptv-$N; pause; }

activate_channel(){ read -rp "Nome: " N; systemctl restart iptv-$N; pause; }

activate_all(){
    while IFS="|" read -r N L Q; do
        systemctl restart iptv-$N
    done < "$DB"
    pause
}

remove_channel(){
    read -rp "Nome: " N
    systemctl stop iptv-$N
    systemctl disable iptv-$N
    rm -f /etc/systemd/system/iptv-$N.service
    rm -f "$HLS/$N.m3u8"
    rm -f "$HLS/$N"*.ts
    rm -f "/root/iptv_pro/run-$N.sh"
    sed -i "/^$N|/d" "$DB"
    systemctl daemon-reload
    pause
}

export_playlist(){
    IP=$(hostname -I | awk '{print $1}')
    echo "#EXTM3U" > "$PLAYLIST"
    while IFS="|" read -r N L Q; do
        echo "#EXTINF:-1,$N" >> "$PLAYLIST"
        echo "http://$IP:8080/$N.m3u8" >> "$PLAYLIST"
    done < "$DB"
    pause
}

clean_segments(){ find "$HLS" -name "*.ts" -mmin +10 -delete; pause; }

backup(){ tar -czf "$BASE/backup/full.tar.gz" "$BASE"; pause; }

restart_hls(){ systemctl restart nginx; pause; }

menu(){
while true
do
clear
echo "===== IPTV PRO FIX ====="
echo "1) Add canal"
echo "2) Stop canal"
echo "3) Export playlist"
echo "4) Limpar segmentos"
echo "5) Backup"
echo "6) Listar canais"
echo "7) Remover canal"
echo "8) Ativar canal"
echo "9) Ativar todos"
echo "0) Sair"

read -rp "Opção: " OP

case "$OP" in
1) add_channel ;;
2) stop_channel ;;
3) export_playlist ;;
4) clean_segments ;;
5) backup ;;
6) list_channels ;;
7) remove_channel ;;
8) activate_channel ;;
9) activate_all ;;
0) exit ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo "INSTALAÇÃO FINALIZADA COM QUALIDADE PRESERVADA"
echo "Digite: menu"
