#!/usr/bin/env bash

set -e

BASE="/root/iptv_pro"
DB="$BASE/channels.db"
STREAM_DIR="/var/www/iptv/streams"
MENU="/usr/local/bin/menu"

apt update -y
apt install -y curl python3

curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
-o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp

mkdir -p "$STREAM_DIR"
mkdir -p "$BASE"
touch "$DB"

# ================= MENU =================

cat > "$MENU" <<'EOF'
#!/usr/bin/env bash

BASE="/root/iptv_pro"
DB="$BASE/channels.db"
STREAM_DIR="/var/www/iptv/streams"

pause(){ read -rp "ENTER..."; }

sanitize(){ echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_'; }

select_quality(){
    echo "Qualidade:"
    echo "1) 480p"
    echo "2) 720p"
    echo "3) 1080p"
    echo "4) Best"
    read -rp "Opção: " Q

    case "$Q" in
        1) QUALITY="best[height<=480]" ;;
        2) QUALITY="best[height<=720]" ;;
        3) QUALITY="best[height<=1080]" ;;
        *) QUALITY="best" ;;
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

while true
do

URL=\$(/usr/local/bin/yt-dlp -f "$QUALITY" -g "$LINK" 2>/dev/null)

if [ -z "\$URL" ]; then
    sleep 5
    continue
fi

echo "\$URL" > "$STREAM_DIR/$NAME.url"

# mantém atualizado
sleep 60
done
EOF2

    chmod +x "$SCRIPT"

    cat > "$SERVICE" <<EOF2
[Unit]
Description=IPTV Direct Stream $NAME
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
    read -rp "Nome do canal: " NAME
    NAME=$(sanitize "$NAME")

    read -rp "Link: " LINK

    select_quality

    echo "$NAME|$LINK|$QUALITY" >> "$DB"

    create_service "$NAME" "$LINK" "$QUALITY"

    echo "Canal criado (STREAM DIRETO)"
    pause
}

list_channels(){
    cut -d "|" -f1 "$DB"
    pause
}

show_links(){
    IP=$(hostname -I | awk '{print $1}')

    echo "Links IPTV:"
    echo

    while IFS="|" read -r NAME LINK QUALITY
    do
        echo "$NAME"
        echo "http://$IP:8080/streams/$NAME.url"
        echo
    done < "$DB"

    pause
}

stop_channel(){
    read -rp "Nome: " N
    systemctl stop iptv-$N
    pause
}

start_channel(){
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
    rm -f "$STREAM_DIR/$N.url"

    sed -i "/^$N|/d" "$DB"

    systemctl daemon-reload

    pause
}

menu(){
while true
do
clear
echo "==== IPTV DIRECT STREAM ===="
echo "1 Add canal"
echo "2 Stop canal"
echo "3 Start canal"
echo "4 Listar"
echo "5 Links"
echo "6 Remover"
echo "0 Sair"
read -rp "Opção: " OP

case $OP in
1) add_channel ;;
2) stop_channel ;;
3) start_channel ;;
4) list_channels ;;
5) show_links ;;
6) remove_channel ;;
0) exit ;;
esac
done
}

menu
EOF

chmod +x "$MENU"

echo "INSTALAÇÃO FINALIZADA"
echo "rode: menu"
