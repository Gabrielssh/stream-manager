#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER INSTALL + MENU
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

select_quality(){
    QUALITY='best'
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
URL=\$(/usr/local/bin/yt-dlp --no-playlist -f "$QUALITY" -g "$LINK" 2>/dev/null)

if [ -z "\$URL" ]; then
    sleep 5
    continue
fi

mkdir -p "\$HLS/$NAME"

/usr/bin/ffmpeg -loglevel error -re -i "\$URL" \\
-filter_complex "\
[0:v]split=4[v1][v2][v3][v4]; \
[v1]scale=640:360[v360]; \
[v2]scale=854:480[v480]; \
[v3]scale=1280:720[v720]; \
[v4]scale=1920:1080[v1080]" \\
-map "[v360]" -map a -c:v:0 libx264 -preset veryfast -b:v:0 800k \\
-map "[v480]" -map a -c:v:1 libx264 -preset veryfast -b:v:1 1200k \\
-map "[v720]" -map a -c:v:2 libx264 -preset veryfast -b:v:2 2500k \\
-map "[v1080]" -map a -c:v:3 libx264 -preset veryfast -b:v:3 4500k \\
-c:a aac -ar 48000 -ac 2 \\
-f hls \\
-hls_time 4 \\
-hls_playlist_type event \\
-hls_flags independent_segments \\
-master_pl_name master.m3u8 \\
-var_stream_map "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3" \\
"\$HLS/$NAME/%v/index.m3u8"

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

# ================= FUNÇÕES =================

add_channel(){
    clear
    read -rp "Nome do canal: " NAME
    NAME=$(sanitize "$NAME")

    read -rp "Link: " LINK
    LINK=$(normalize_link "$LINK")

    select_quality

    echo "$NAME|$LINK|$QUALITY" >> "$DB"

    create_service "$NAME" "$LINK" "$QUALITY"

    echo "Canal iniciado"
    pause
}

export_links_backup(){
    DATE=$(date +%Y%m%d_%H%M%S)
    cp "$DB" "$BACKUP_DIR/links_backup_$DATE.db"
    pause
}

import_links_backup(){
    read -rp "Arquivo: " FILE
    cp "$BACKUP_DIR/$FILE" "$DB"
    while IFS="|" read -r NAME LINK QUALITY
    do
        create_service "$NAME" "$LINK" "$QUALITY"
    done < "$DB"
    pause
}

stop_channel(){ read -rp "Nome: " NAME; systemctl stop iptv-$NAME; pause; }
activate_channel(){ read -rp "Nome: " NAME; systemctl restart iptv-$NAME; pause; }

activate_all(){
    while IFS="|" read -r NAME LINK QUALITY
    do systemctl restart iptv-$NAME; done < "$DB"
    pause
}

remove_channel(){
    read -rp "Nome: " NAME
    systemctl stop iptv-$NAME
    systemctl disable iptv-$NAME
    rm -f /etc/systemd/system/iptv-$NAME.service
    rm -rf "$HLS/$NAME"
    sed -i "/^$NAME|/d" "$DB"
    systemctl daemon-reload
    pause
}

delete_channel(){ remove_channel; }

auto_clean_segments(){
    while true
    do
        find "$HLS" -name "*.ts" -mmin +5 -delete
        sleep 300
    done
}

list_channels(){ cut -d "|" -f1 "$DB"; pause; }

show_links(){
    IP=$(hostname -I | awk '{print $1}')
    while IFS="|" read -r NAME LINK QUALITY
    do
        echo "$NAME"
        echo "http://$IP:8080/$NAME/master.m3u8"
        echo
    done < "$DB"
    pause
}

export_playlist(){
    IP=$(hostname -I | awk '{print $1}')
    echo "#EXTM3U" > "$PLAYLIST"
    while IFS="|" read -r NAME LINK QUALITY
    do
        echo "#EXTINF:-1,$NAME" >> "$PLAYLIST"
        echo "http://$IP:8080/$NAME/master.m3u8" >> "$PLAYLIST"
    done < "$DB"
    pause
}

clean_segments(){ find "$HLS" -name "*.ts" -delete; pause; }

backup(){ tar -czf "$BASE/backup/full.tar.gz" "$BASE"; pause; }

restart_hls(){ systemctl restart nginx; pause; }

show_off(){
    while IFS="|" read -r NAME LINK QUALITY
    do
        systemctl is-active iptv-$NAME >/dev/null || echo "$NAME OFF"
    done < "$DB"
    pause
}

show_uptime(){
    while IFS="|" read -r NAME LINK QUALITY
    do
        systemctl show iptv-$NAME --property=ActiveEnterTimestamp
    done < "$DB"
    pause
}

show_viewers(){ echo "Logs nginx"; pause; }
show_mbps(){ echo "Mbps calculado"; pause; }

menu(){
while true
do
clear
echo "1) Adicionar canal"
echo "2) Parar canal"
echo "3) Exportar playlist"
echo "4) Limpar segmentos"
echo "5) Backup completo"
echo "6) Listar canais"
echo "7) Remover canal"
echo "8) Ver links"
echo "9) Reiniciar servidor HLS"
echo "10) Exportar backup de links"
echo "11) Importar backup de links"
echo "12) Ativar canal"
echo "13) Ativar todos canais"
echo "14) Mostrar canais OFF"
echo "15) Tempo online"
echo "16) Usuários assistindo"
echo "17) Consumo Mbps por canal"
echo "18) Monitoramento (glances)"
echo "19) Excluir canal criado"
echo "20) Limpeza automática"
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
8) show_links ;;
9) restart_hls ;;
10) export_links_backup ;;
11) import_links_backup ;;
12) activate_channel ;;
13) activate_all ;;
14) show_off ;;
15) show_uptime ;;
16) show_viewers ;;
17) show_mbps ;;
18) glances ;;
19) delete_channel ;;
20) auto_clean_segments ;;
0) exit ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo "INSTALADO - digite: menu"
