#!/usr/bin/env bash

set -e

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"
MENU="/usr/local/bin/menu"

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

systemctl restart nginx
systemctl enable nginx

# ================= MENU =================

cat > "$MENU" <<'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"

pause(){ read -rp "ENTER..."; }

sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

normalize_link(){
    echo "$1" | cut -d "&" -f1
}

select_quality(){
    echo "Qualidade:"
    echo "1) 480p"
    echo "2) 720p"
    echo "3) 1080p"
    echo "4) Best"
    read -rp "Opção: " Q

    case "$Q" in
        1) QUALITY="bv*[height<=480]+ba/best[height<=480]" ;;
        2) QUALITY="bv*[height<=720]+ba/best[height<=720]" ;;
        3) QUALITY="bv*[height<=1080]+ba/best[height<=1080]" ;;
        *) QUALITY="bv*+ba/best" ;;
    esac
}

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

URL_VIDEO=\$(yt-dlp -f "$QUALITY" -g "$LINK" 2>/dev/null | head -n 1)
URL_AUDIO=\$(yt-dlp -f "$QUALITY" -g "$LINK" 2>/dev/null | tail -n 1)

if [ -z "\$URL_VIDEO" ]; then
    sleep 5
    continue
fi

ffmpeg -hide_banner -loglevel error -re \
-i "\$URL_VIDEO" \
-i "\$URL_AUDIO" \
-map 0:v:0 -map 1:a:0 \
-c:v copy \
-c:a aac -b:a 128k \
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
Description=IPTV $NAME
After=network.target

[Service]
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
    read -rp "Nome: " NAME
    NAME=$(sanitize "$NAME")

    read -rp "Link: " LINK
    LINK=$(normalize_link "$LINK")

    select_quality

    echo "$NAME|$LINK|$QUALITY" >> "$DB"

    create_service "$NAME" "$LINK" "$QUALITY"

    echo "Canal ativo!"
    pause
}

list_channels(){
    cut -d "|" -f1 "$DB"
    pause
}

stop_channel(){
    read -rp "Nome: " N
    systemctl stop iptv-$N
    pause
}

activate_channel(){
    read -rp "Nome: " N
    systemctl restart iptv-$N
    pause
}

remove_channel(){
    read -rp "Nome: " N
    systemctl stop iptv-$N
    systemctl disable iptv-$N
    rm -f /etc/systemd/system/iptv-$N.service
    rm -f /root/iptv_pro/run-$N.sh
    rm -f "$HLS/$N.m3u8"
    rm -f "$HLS/$N"*.ts
    sed -i "/^$N|/d" "$DB"
    systemctl daemon-reload
    pause
}

export_playlist(){
    IP=$(hostname -I | awk '{print $1}')
    echo "#EXTM3U" > "$BASE/playlist.m3u"

    while IFS="|" read -r N L Q
    do
        echo "#EXTINF:-1,$N" >> "$BASE/playlist.m3u"
        echo "http://$IP:8080/$N.m3u8" >> "$BASE/playlist.m3u"
    done < "$DB"

    echo "OK"
    pause
}

menu(){
while true
do
clear
echo "==== IPTV PRO ===="
echo "1 Add"
echo "2 Stop"
echo "3 Playlist"
echo "4 List"
echo "5 Remove"
echo "6 Start"
echo "0 Exit"
read -rp "Opção: " OP

case $OP in
1) add_channel ;;
2) stop_channel ;;
3) export_playlist ;;
4) list_channels ;;
5) remove_channel ;;
6) activate_channel ;;
0) exit ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo "INSTALAÇÃO OK"
echo "rode: menu"
