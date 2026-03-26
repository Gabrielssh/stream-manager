#!/usr/bin/env bash

set -e

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"
MENU="/usr/local/bin/menu"

[ "$EUID" -ne 0 ] && echo "Execute como root" && exit 1

apt update -y
apt install -y ffmpeg nginx curl vnstat python3 glances

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$HLS" "$BASE/backup" "$BASE/logs"
touch "$DB"

chown -R www-data:www-data /var/www/iptv
chmod -R 755 /var/www/iptv

# NGINX
cat > /etc/nginx/sites-available/iptv <<EOF
server {
    listen 8080 default_server;
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
nginx -t && systemctl restart nginx && systemctl enable nginx

# GUARDIAN
cat > /usr/local/bin/iptv-guardian << 'EOF'
#!/usr/bin/env bash
HLS="/var/www/iptv/hls"
BASE="/root/iptv_pro"

while true
do
    USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

    if [ "$USAGE" -ge 85 ]; then
        find "$HLS" -name "*.ts" -mmin +2 -delete
        > /var/log/nginx/access.log
        > /var/log/nginx/error.log
        journalctl --vacuum-time=1d
        apt clean
        ls -t "$BASE/backup"/* 2>/dev/null | tail -n +6 | xargs -r rm -f
    fi

    sleep 60
done
EOF

chmod +x /usr/local/bin/iptv-guardian

cat > /etc/systemd/system/iptv-guardian.service <<EOF
[Service]
ExecStart=/usr/local/bin/iptv-guardian
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iptv-guardian
systemctl start iptv-guardian

# MENU
cat > "$MENU" << 'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
DB="$BASE/channels.db"
PLAYLIST="$BASE/playlist.m3u"
BACKUP_DIR="$BASE/backup"

pause(){ read -rp "ENTER..."; }
sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

# CORE
create_service(){
NAME="$1"; LINK="$2"; QUALITY="$3"
SCRIPT="/root/iptv_pro/run-$NAME.sh"

cat > "$SCRIPT" <<EOF2
#!/usr/bin/env bash
while true
do
URL=\$(yt-dlp -f "$QUALITY" -g "$LINK" 2>/dev/null)
[ -z "\$URL" ] && sleep 5 && continue

ffmpeg -loglevel error -re -i "\$URL" \
-c:v copy -c:a aac -f hls \
-hls_time 4 -hls_list_size 6 \
-hls_flags delete_segments+append_list \
"$HLS/$NAME.m3u8"

sleep 5
done
EOF2

chmod +x "$SCRIPT"

cat > /etc/systemd/system/iptv-$NAME.service <<EOF2
[Service]
ExecStart=$SCRIPT
Restart=always
EOF2

systemctl daemon-reload
systemctl enable iptv-$NAME
systemctl restart iptv-$NAME
}

# FUNÇÕES
add_channel(){ read -rp "Nome: " N; read -rp "Link: " L; N=$(sanitize "$N"); echo "$N|$L|best" >> "$DB"; create_service "$N" "$L" best; pause; }
stop_channel(){ read -rp "Nome: " N; systemctl stop iptv-$N; pause; }
export_playlist(){ IP=$(hostname -I|awk '{print $1}'); echo "#EXTM3U" > "$PLAYLIST"; while IFS="|" read -r N L Q; do echo "#EXTINF:-1,$N" >> "$PLAYLIST"; echo "http://$IP:8080/$N.m3u8" >> "$PLAYLIST"; done < "$DB"; pause; }
clean_segments(){ find "$HLS" -name "*.ts" -mmin +10 -delete; pause; }
backup(){ tar -czf "$BASE/backup/full.tar.gz" "$BASE"; pause; }
list_channels(){ cut -d "|" -f1 "$DB"; pause; }

remove_channel(){
read -rp "Nome: " N
systemctl stop iptv-$N 2>/dev/null
systemctl disable iptv-$N 2>/dev/null
rm -f /etc/systemd/system/iptv-$N.service "$HLS/$N"* "/root/iptv_pro/run-$N.sh"
sed -i "/^$N|/d" "$DB"
systemctl daemon-reload
pause
}

show_links(){ IP=$(hostname -I|awk '{print $1}'); while IFS="|" read -r N L Q; do echo "$N -> http://$IP:8080/$N.m3u8"; done < "$DB"; pause; }
restart_hls(){ systemctl restart nginx; pause; }

export_links_backup(){ cp "$DB" "$BACKUP_DIR/links_$(date +%s).db"; pause; }

import_links_backup(){
ls "$BACKUP_DIR"
read -rp "Arquivo: " F
cp "$BACKUP_DIR/$F" "$DB"
while IFS="|" read -r N L Q; do create_service "$N" "$L" "$Q"; done < "$DB"
pause
}

activate_channel(){ read -rp "Nome: " N; systemctl restart iptv-$N; pause; }

activate_all(){ while IFS="|" read -r N L Q; do systemctl restart iptv-$N; done < "$DB"; pause; }

show_off(){ while IFS="|" read -r N L Q; do systemctl is-active --quiet iptv-$N || echo "$N OFF"; done < "$DB"; pause; }

show_uptime(){ while IFS="|" read -r N L Q; do systemctl show iptv-$N --property=ActiveEnterTimestamp; done < "$DB"; pause; }

show_viewers(){ grep ".m3u8" /var/log/nginx/access.log | wc -l; pause; }

show_mbps(){ awk '{sum+=$10} END {print sum/1024/1024 " MB"}' /var/log/nginx/access.log; pause; }

delete_channel(){ remove_channel; }

auto_clean_segments(){
read -rp "Min: " I; I=${I:-5}
while true; do find "$HLS" -name "*.ts" -mmin +"$I" -delete; sleep $((I*60)); done
}

# OPÇÃO 21
clean_nginx_logs(){
echo "1 Manual 2 Auto"
read OP
[ "$OP" = "1" ] && > /var/log/nginx/access.log
[ "$OP" = "2" ] && while true; do > /var/log/nginx/access.log; sleep 600; done
pause
}

# OPÇÃO 22
guardian_control(){
echo "1 Status 2 Restart 3 Stop 4 Start"
read OP
case "$OP" in
1) systemctl status iptv-guardian --no-pager ;;
2) systemctl restart iptv-guardian ;;
3) systemctl stop iptv-guardian ;;
4) systemctl start iptv-guardian ;;
esac
pause
}

menu(){
while true
do
clear
echo "IPTV PRO"
echo "1 Add canal"
echo "2 Stop canal"
echo "3 Playlist"
echo "4 Limpar TS"
echo "5 Backup"
echo "6 Lista"
echo "7 Remover"
echo "8 Links"
echo "9 Reiniciar HLS"
echo "10 Backup links"
echo "11 Importar"
echo "12 Ativar"
echo "13 Ativar todos"
echo "14 OFF"
echo "15 Uptime"
echo "16 Users"
echo "17 Mbps"
echo "18 Glances"
echo "19 Excluir"
echo "20 Auto TS"
echo "21 Logs nginx"
echo "22 Guardian"
echo "0 Sair"

read OP

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
21) clean_nginx_logs ;;
22) guardian_control ;;
0) exit ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo "Instalação concluída. Digite: menu"
