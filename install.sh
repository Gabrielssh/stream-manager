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
        1) QUALITY='best[height<=360]' ;;
        2) QUALITY='best[height<=480]' ;;
        3) QUALITY='best[height<=720]' ;;
        4) QUALITY='best[height<=1080]' ;;
        5) QUALITY='best' ;;
        *) QUALITY='best' ;;
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
URL=\$(/usr/local/bin/yt-dlp --no-playlist -f "$QUALITY" -g "$LINK" 2>/dev/null)
if [ -z "\$URL" ]; then
    sleep 5
    continue
fi
/usr/bin/ffmpeg -loglevel error -re -i "\$URL" \
-c:v copy \
-c:a aac \
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
    echo "Backup criado em:"
    echo "$BACKUP_DIR/links_backup_$DATE.db"
    pause
}

import_links_backup(){
    echo "Backups disponíveis:"
    ls -1 "$BACKUP_DIR"/links_backup_*.db 2>/dev/null || echo "Nenhum backup encontrado"
    echo
    read -rp "Digite o nome completo do arquivo: " FILE

    FULL_PATH="$BACKUP_DIR/$FILE"

    if [ -f "$FULL_PATH" ]; then
        cp "$FULL_PATH" "$DB"
        echo "Backup importado com sucesso!"

        while IFS="|" read -r NAME LINK QUALITY
        do
            create_service "$NAME" "$LINK" "$QUALITY"
        done < "$DB"

        echo "Serviços recriados."
    else
        echo "Arquivo não encontrado!"
    fi

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
    while IFS="|" read -r NAME LINK QUALITY
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
    rm -f "/root/iptv_pro/run-$NAME.sh"
    sed -i "/^$NAME|/d" "$DB"
    systemctl daemon-reload
    pause
}

delete_channel(){
    clear
    cut -d "|" -f1 "$DB"
    read -rp "Nome: " NAME
    NAME=$(sanitize "$NAME")

    systemctl stop iptv-$NAME 2>/dev/null
    systemctl disable iptv-$NAME 2>/dev/null
    rm -f /etc/systemd/system/iptv-$NAME.service
    rm -f "$HLS/$NAME.m3u8"
    rm -f "$HLS/$NAME"*.ts
    rm -f "/root/iptv_pro/run-$NAME.sh"
    sed -i "/^$NAME|/d" "$DB"
    systemctl daemon-reload
    pause
}

auto_clean_segments(){
    read -rp "Intervalo minutos: " INTERVAL
    INTERVAL=${INTERVAL:-5}
    while true
    do
        find "$HLS" -name "*.ts" -mmin +"$INTERVAL" -delete
        sleep "$((INTERVAL * 60))"
    done
}

# ===== NOVA FUNÇÃO 21 =====

clean_nginx_logs(){
    echo
    echo "1) Limpar agora"
    echo "2) Automático"
    read -rp "Opção: " TYPE

    LOG="/var/log/nginx/access.log"

    case "$TYPE" in
        1)
            > "$LOG"
            echo "Logs limpos!"
            pause
        ;;
        2)
            read -rp "Intervalo minutos: " INTERVAL
            INTERVAL=${INTERVAL:-10}
            while true
            do
                > "$LOG"
                sleep "$((INTERVAL * 60))"
            done
        ;;
    esac
}

menu(){
    while true
    do
        clear
        echo "IPTV PRO SERVER"
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
        echo "10) Backup links"
        echo "11) Importar links"
        echo "12) Ativar canal"
        echo "13) Ativar todos"
        echo "14) Canais OFF"
        echo "15) Uptime"
        echo "16) Usuários"
        echo "17) Mbps"
        echo "18) Glances"
        echo "19) Excluir canal"
        echo "20) Auto limpar TS"
        echo "21) Limpar logs Nginx"
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
            21) clean_nginx_logs ;;
            0) exit ;;
        esac
    done
}

menu
EOF

chmod +x "$MENU"

echo "Instalação concluída. Digite: menu"
