#!/usr/bin/env bash

# =====================================
# IPTV PRO ELITE v3.0 - MATRIX LAYOUT
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

        echo "Serviços systemd recriados. Todos os canais podem ser ativados."
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
    echo "Canais disponíveis:"
    cut -d "|" -f1 "$DB"
    echo
    read -rp "Digite o nome do canal que deseja excluir: " NAME
    NAME=$(sanitize "$NAME")

    if grep -q "^$NAME|" "$DB"; then
        systemctl stop iptv-$NAME 2>/dev/null
        systemctl disable iptv-$NAME 2>/dev/null
        rm -f /etc/systemd/system/iptv-$NAME.service
        rm -f "$HLS/$NAME.m3u8"
        rm -f "$HLS/$NAME"*.ts
        rm -f "/root/iptv_pro/run-$NAME.sh"
        sed -i "/^$NAME|/d" "$DB"
        systemctl daemon-reload
        echo "Canal '$NAME' excluído com sucesso!"
    else
        echo "Canal '$NAME' não encontrado!"
    fi
    pause
}

auto_clean_segments(){
    echo
    echo "Defina o tempo (em minutos) para limpeza automática dos segmentos .ts"
    read -rp "Intervalo (minutos): " INTERVAL
    INTERVAL=${INTERVAL:-5}
    echo "Iniciando limpeza automática a cada $INTERVAL minutos. Pressione CTRL+C para parar."
    while true
    do
        find "$HLS" -name "*.ts" -mmin +"$INTERVAL" -delete
        sleep "$((INTERVAL * 60))"
    done
}

list_channels(){
    cut -d "|" -f1 "$DB"
    pause
}

show_links(){
    IP=$(hostname -I | awk '{print $1}')
    while IFS="|" read -r NAME LINK QUALITY
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
    while IFS="|" read -r NAME LINK QUALITY
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
    tar -czf "$BASE/backup/iptv_full_backup.tar.gz" "$BASE"
    echo "Backup completo criado."
    pause
}

restart_hls(){
    systemctl restart nginx
    pause
}

show_off(){
    while IFS="|" read -r NAME LINK QUALITY
    do
        if ! systemctl is-active --quiet iptv-$NAME; then
            echo "$NAME OFF"
        fi
    done < "$DB"
    pause
}

show_uptime(){
    while IFS="|" read -r NAME LINK QUALITY
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
    GREEN='\033[1;32m'
    NC='\033[0m'
    while true
    do
        clear
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} ███████╗██████╗ ███████╗████████╗ ██╗   ██╗███████╗         ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC} ██╔════╝██╔══██╗██╔════╝╚══██╔══╝ ██║   ██║██╔════╝         ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC} █████╗  ██████╔╝█████╗     ██║    ██║   ██║█████╗           ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC} ██╔══╝  ██╔═══╝ ██╔══╝     ██║    ██║   ██║██╔══╝           ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC} ███████╗██║     ███████╗   ██║    ╚██████╔╝███████╗         ${GREEN}║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"

        printf "${GREEN}║ 1) Adicionar canal                                         ║${NC}\n"
        printf "${GREEN}║ 2) Parar canal                                             ║${NC}\n"
        printf "${GREEN}║ 3) Exportar playlist                                       ║${NC}\n"
        printf "${GREEN}║ 4) Limpar segmentos                                        ║${NC}\n"
        printf "${GREEN}║ 5) Backup completo                                         ║${NC}\n"
        printf "${GREEN}║ 6) Listar canais                                           ║${NC}\n"
        printf "${GREEN}║ 7) Remover canal                                           ║${NC}\n"
        printf "${GREEN}║ 8) Ver links                                               ║${NC}\n"
        printf "${GREEN}║ 9) Reiniciar servidor HLS                                  ║${NC}\n"
        printf "${GREEN}║ 10) Exportar backup de links                                ║${NC}\n"
        printf "${GREEN}║ 11) Importar backup de links                                ║${NC}\n"
        printf "${GREEN}║ 12) Ativar canal                                            ║${NC}\n"
        printf "${GREEN}║ 13) Ativar todos canais                                     ║${NC}\n"
        printf "${GREEN}║ 14) Mostrar canais OFF                                      ║${NC}\n"
        printf "${GREEN}║ 15) Tempo online                                            ║${NC}\n"
        printf "${GREEN}║ 16) Usuários assistindo                                     ║${NC}\n"
        printf "${GREEN}║ 17) Consumo Mbps por canal                                  ║${NC}\n"
        printf "${GREEN}║ 18) Monitoramento CPU/RAM/NET (Glances)                    ║${NC}\n"
        printf "${GREEN}║ 19) Excluir canal criado                                    ║${NC}\n"
        printf "${GREEN}║ 20) Limpeza automática de segmentos .ts                     ║${NC}\n"
        echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
        printf "${GREEN}║ 0) Sair                                                    ║${NC}\n"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo

        read -rp "Selecione uma opção: " OP

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

echo
echo "================================="
echo " IPTV PRO ELITE v3.0 INSTALADO!"
echo "================================="
echo
echo "Digite: menu"
