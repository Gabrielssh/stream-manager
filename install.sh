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
NGINX_CONF="/etc/nginx/sites-available/iptv"

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

cat > $NGINX_CONF <<EOF
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

ln -sf $NGINX_CONF /etc/nginx/sites-enabled/iptv
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
NGINX_CONF="/etc/nginx/sites-available/iptv"

pause(){ read -rp "Pressione ENTER..."; }

sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

normalize_link(){
    echo "$1" | sed 's#m.youtube.com#www.youtube.com#g' | cut -d "&" -f1
}

get_port(){
    grep listen $NGINX_CONF | head -n1 | awk '{print $2}'
}

# ================= ALTERAR PORTA =================

alter_port(){
    read -rp "Nova porta: " PORT
    [[ ! "$PORT" =~ ^[0-9]+$ ]] && echo "Porta inválida!" && pause && return

    sed -i "s/listen .*/listen $PORT default_server;/" $NGINX_CONF
    sed -i "s/listen \[::\].*/listen [::]:$PORT default_server;/" $NGINX_CONF

    nginx -t && systemctl restart nginx
    echo "Porta alterada para $PORT"
    pause
}

# ================= QUALIDADE =================

select_quality(){
    echo "1) 360p"
    echo "2) 480p"
    echo "3) 720p"
    echo "4) 1080p"
    echo "5) Melhor"
    read -rp "Opção: " Q
    case "$Q" in
        1) QUALITY='best[height<=360]' ;;
        2) QUALITY='best[height<=480]' ;;
        3) QUALITY='best[height<=720]' ;;
        4) QUALITY='best[height<=1080]' ;;
        *) QUALITY='best' ;;
    esac
}

# ================= SERVICE =================

create_service(){

NAME="$1"
LINK="$2"
QUALITY="$3"

SCRIPT="$BASE/run-$NAME.sh"
SERVICE="/etc/systemd/system/iptv-$NAME.service"

cat > "$SCRIPT" <<EOF2
#!/usr/bin/env bash
HLS="$HLS"

while true
do
URL=\$(/usr/local/bin/yt-dlp --no-playlist -f "$QUALITY" -g "$LINK" 2>/dev/null)

if [ -z "\$URL" ]; then
    sleep 5
    continue
fi

/usr/bin/ffmpeg -loglevel error -re -i "\$URL" \
-c:v copy -c:a aac \
-f hls \
-hls_time 4 \
-hls_list_size 6 \
-hls_flags delete_segments+append_list \
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

# ================= FUNÇÕES =================

add_channel(){
    read -rp "Nome do canal: " NAME
    NAME=$(sanitize "$NAME")

    if grep -q "^$NAME|" "$DB"; then
        echo "Canal já existe!"
        pause
        return
    fi

    read -rp "Link: " LINK
    LINK=$(normalize_link "$LINK")

    select_quality

    echo "$NAME|$LINK|$QUALITY" >> "$DB"
    create_service "$NAME" "$LINK" "$QUALITY"

    echo "Canal iniciado!"
    pause
}

stop_channel(){ read -rp "Nome: " NAME; systemctl stop iptv-$NAME; pause; }
activate_channel(){ read -rp "Nome: " NAME; systemctl restart iptv-$NAME; pause; }

activate_all(){
while IFS="|" read -r NAME LINK QUALITY
do systemctl restart iptv-$NAME; done < "$DB"
pause
}

list_channels(){ cut -d "|" -f1 "$DB"; pause; }

show_links(){
IP=$(hostname -I | awk '{print $1}')
PORT=$(get_port)

while IFS="|" read -r NAME LINK QUALITY
do
echo "$NAME"
echo "http://$IP:$PORT/$NAME.m3u8"
echo
done < "$DB"
pause
}

clean_segments(){ find "$HLS" -name "*.ts" -mmin +10 -delete; pause; }

auto_clean_segments(){
read -rp "Intervalo minutos: " INTERVAL
INTERVAL=${INTERVAL:-5}
nohup bash -c "while true; do find $HLS -name '*.ts' -mmin +$INTERVAL -delete; sleep $((INTERVAL*60)); done" >/dev/null 2>&1 &
echo "Limpeza automática ativada."
pause
}

delete_channel(){
read -rp "Nome: " NAME
systemctl stop iptv-$NAME 2>/dev/null
systemctl disable iptv-$NAME 2>/dev/null
rm -f /etc/systemd/system/iptv-$NAME.service
rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts
rm -f "$BASE/run-$NAME.sh"
sed -i "/^$NAME|/d" "$DB"
systemctl daemon-reload
echo "Canal removido!"
pause
}

cpu_per_channel(){
while IFS="|" read -r NAME LINK QUALITY
do
PID=$(systemctl show -p MainPID --value iptv-$NAME)
[ "$PID" -gt 0 ] && ps -p $PID -o %cpu=
echo "$NAME"
done < "$DB"
pause
}

traffic_real_time(){ watch -n 2 vnstat -l; }

professional_panel(){
clear
echo "===== PAINEL PROFISSIONAL ====="
echo "CPU:"; top -bn1 | grep "Cpu(s)"
echo
echo "RAM:"; free -h
echo
echo "DISCO:"; df -h /
pause
}

# ================= MENU =================

menu(){
while true
do
clear
echo " IPTV PRO SERVER"
echo
echo "1) Adicionar canal"
echo "2) Parar canal"
echo "3) Exportar playlist"
echo "4) Limpar segmentos"
echo "5) Backup completo"
echo "6) Listar canais"
echo "7) Remover canal"
echo "8) Ver links"
echo "9) Reiniciar HLS"
echo "10) Exportar backup links"
echo "11) Importar backup links"
echo "12) Ativar canal"
echo "13) Ativar todos"
echo "14) Mostrar OFF"
echo "15) Tempo online"
echo "16) Usuários assistindo"
echo "17) Mbps por canal"
echo "18) Monitoramento Glances"
echo "19) Excluir canal"
echo "20) Limpeza automática"
echo "21) Alterar porta"
echo "22) Uso CPU por canal"
echo "23) Painel profissional"
echo "24) Tráfego tempo real"
echo "0) Sair"
echo

read -rp "Opção: " OP

case "$OP" in
1) add_channel ;;
2) stop_channel ;;
3) echo "Use opção 8 para links."; pause ;;
4) clean_segments ;;
5) tar -czf "$BASE/backup/iptv_full_backup.tar.gz" "$BASE"; pause ;;
6) list_channels ;;
7) delete_channel ;;
8) show_links ;;
9) systemctl restart nginx; pause ;;
12) activate_channel ;;
13) activate_all ;;
18) glances ;;
19) delete_channel ;;
20) auto_clean_segments ;;
21) alter_port ;;
22) cpu_per_channel ;;
23) professional_panel ;;
24) traffic_real_time ;;
0) exit ;;
*) echo "Opção inválida"; pause ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo
echo "INSTALAÇÃO CONCLUÍDA"
echo "Digite: menu"
