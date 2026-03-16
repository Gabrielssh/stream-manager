#!/usr/bin/env bash

# =====================================
# IPTV PRO SERVER AUTO INSTALL (FINAL)
# =====================================

set -e

BASE="/root/iptv_pro"
HLS="/var/www/iptv/hls"
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

chown -R www-data:www-data /var/www/iptv
chmod -R 755 /var/www/iptv

# =====================================
# CONFIGURAR NGINX (CORRIGIDO 404)
# =====================================

echo "[+] Configurando Nginx..."

cat > /etc/nginx/sites-available/iptv <<EOF
server {

    listen 8080 default_server;
    listen [::]:8080 default_server;

    server_name _;

    root /var/www/iptv/hls;
    index index.m3u8 index.html;

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

# =====================================
# CRIAR MENU IPTV (DAEMON)
# =====================================

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

cat > /etc/systemd/system/iptv-$NAME.service <<EOL
[Unit]
Description=IPTV Channel $NAME
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do URL=\$(yt-dlp -f best -g "$LINK" 2>/dev/null); if [ -n "\$URL" ]; then ffmpeg -loglevel error -re -i "\$URL" -c:v copy -c:a aac -f hls -hls_time 4 -hls_list_size 6 -hls_flags delete_segments "$HLS/$NAME.m3u8"; fi; sleep 5; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable iptv-$NAME
systemctl start iptv-$NAME
}

add_channel(){
clear
read -rp "Nome do canal: " NAME
NAME=$(sanitize "$NAME")
read -rp "Link: " LINK
echo "$NAME|$LINK" >> "$DB"
create_service "$NAME" "$LINK"
echo "Canal iniciado em background"
pause
}

stop_channel(){
read -rp "Nome do canal: " NAME
systemctl stop iptv-$NAME 2>/dev/null
pause
}

activate_channel(){
read -rp "Nome do canal: " NAME
systemctl start iptv-$NAME
pause
}

activate_all(){
while IFS="|" read -r NAME LINK; do
systemctl start iptv-$NAME
done < "$DB"
echo "Todos ativados"
pause
}

list_channels(){
cut -d "|" -f1 "$DB"
pause
}

remove_channel(){
read -rp "Nome do canal: " NAME
systemctl stop iptv-$NAME 2>/dev/null
systemctl disable iptv-$NAME 2>/dev/null
rm -f /etc/systemd/system/iptv-$NAME.service
rm -f "$HLS/$NAME.m3u8"
rm -f "$HLS/$NAME"*.ts
sed -i "/^$NAME|/d" "$DB"
systemctl daemon-reload
echo "Canal removido"
pause
}

show_links(){
IP=$(hostname -I | awk '{print $1}')
while IFS="|" read -r NAME LINK; do
echo "$NAME"
echo "http://$IP:8080/$NAME.m3u8"
echo
done < "$DB"
pause
}

export_playlist(){
IP=$(hostname -I | awk '{print $1}')
echo "#EXTM3U" > "$PLAYLIST"
while IFS="|" read -r NAME LINK; do
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
for NAME in $(cut -d "|" -f1 "$DB"); do
if ! systemctl is-active --quiet iptv-$NAME; then
echo "$NAME"
fi
done
pause
}

show_uptime(){
for NAME in $(cut -d "|" -f1 "$DB"); do
echo -n "$NAME | "
systemctl show iptv-$NAME -p ActiveEnterTimestamp | cut -d= -f2
done
pause
}

monitor_ram(){ free -h; pause; }

monitor_net(){ vnstat; pause; }

menu(){

while true; do
clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IPTV PRO SERVER (FINAL)"
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
10) monitor_ram ;;
11) monitor_net ;;
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
echo " INSTALAÇÃO CONCLUÍDA ✅"
echo "================================="
echo
echo "Agora funciona fechado terminal"
echo "Inicia automático no reboot"
echo
echo "Digite:"
echo "menu"
echo
