#!/usr/bin/env bash
# STREAM MANAGER PRO TOTAL 24/7
# Requisitos: ffmpeg, yt-dlp, tmux, coreutils
# Bash >= 4

set -u

BASE_DIR="$HOME/stream_manager"
STREAM_DIR="$BASE_DIR/streams"
LOG_DIR="$BASE_DIR/logs"
SCHEDULE_FILE="$BASE_DIR/schedule.txt"
MAX_LOG_DAYS=30

mkdir -p "$STREAM_DIR" "$LOG_DIR"
touch "$SCHEDULE_FILE"

declare -A STREAMS_PID
declare -A STREAM_HISTORY
declare -A STREAM_CPU
declare -A STREAM_RAM
declare -A STREAM_UPTIME

# -------------------------
# Rotação de logs
# -------------------------
rotate_logs() {
    find "$LOG_DIR" -type f -mtime +"$MAX_LOG_DAYS" -delete 2>/dev/null
}

# -------------------------
# Atualiza métricas
# -------------------------
update_metrics() {
    for NAME in "${!STREAMS_PID[@]}"; do
        PID="${STREAMS_PID[$NAME]}"

        if ps -p "$PID" >/dev/null 2>&1; then
            CPU=$(ps -p "$PID" -o %cpu= | awk '{print int($1)}')
            RAM=$(ps -p "$PID" -o rss= | awk '{printf "%.0f", $1/1024}')

            STREAM_CPU["$NAME"]=$CPU
            STREAM_RAM["$NAME"]=$RAM

            if [ -z "${STREAM_UPTIME[$NAME]:-}" ]; then
                STREAM_UPTIME["$NAME"]="$(date +%s)"
            fi

            echo "$(date +%H:%M:%S) CPU:${CPU}% RAM:${RAM}MB" >> "$LOG_DIR/$NAME-$(date +%F).log"
        else
            STREAM_CPU["$NAME"]=0
            STREAM_RAM["$NAME"]=0
        fi
    done
}

# -------------------------
# Barra ASCII
# -------------------------
draw_bar() {
    local VALUE=$1
    local MAX=$2
    local WIDTH=20

    [ "$MAX" -eq 0 ] && MAX=1
    [ "$VALUE" -gt "$MAX" ] && VALUE="$MAX"

    local FILLED=$(( VALUE * WIDTH / MAX ))
    local EMPTY=$(( WIDTH - FILLED ))

    printf "%0.s#" $(seq 1 "$FILLED")
    printf "%0.s-" $(seq 1 "$EMPTY")
}

# -------------------------
# Dashboard
# -------------------------
dashboard() {
    while true; do
        clear
        update_metrics
        rotate_logs

        echo "===== STREAM MANAGER 24/7 ====="
        echo "Uptime VPS: $(uptime -p)"
        echo "Streams ativas: ${#STREAMS_PID[@]}"
        echo

        printf "%-15s %-6s %-6s %-6s %-8s %-20s %-20s\n" \
            "CANAL" "PID" "CPU%" "RAM" "STATUS" "CPU BAR" "RAM BAR"

        for NAME in "${!STREAMS_PID[@]}"; do
            PID="${STREAMS_PID[$NAME]}"
            STATUS="OFF"

            if ps -p "$PID" >/dev/null 2>&1; then
                STATUS="ON"
            fi

            printf "%-15s %-6s %-6s %-6s %-8s %-20s %-20s\n" \
                "$NAME" "$PID" \
                "${STREAM_CPU[$NAME]:-0}" \
                "${STREAM_RAM[$NAME]:-0}M" \
                "$STATUS" \
                "$(draw_bar "${STREAM_CPU[$NAME]:-0}" 100)" \
                "$(draw_bar "${STREAM_RAM[$NAME]:-0}" 2048)"
        done

        sleep 2
    done
}

# -------------------------
# Monitor automático
# -------------------------
monitor_alerts() {
    for NAME in "${!STREAMS_PID[@]}"; do
        PID="${STREAMS_PID[$NAME]}"

        if ! ps -p "$PID" >/dev/null 2>&1; then
            echo "[ALERTA] Stream '$NAME' caiu. Reiniciando..."
            start_stream <<< "$NAME"
        fi
    done
}

# -------------------------
# Adicionar stream
# -------------------------
add_stream() {
    read -rp "Nome do canal: " NAME
    read -rp "Link (YouTube / HLS / arquivo): " LINK

    OUTPUT="$STREAM_DIR/$NAME.m3u8"

    # HLS direto
    if [[ "$LINK" =~ \.m3u8$ ]]; then
        ffmpeg -re -i "$LINK" -c copy -f hls -hls_time 10 -hls_list_size 0 "$OUTPUT" \
            >/dev/null 2>&1 &

    # YouTube
    elif [[ "$LINK" =~ youtu ]]; then
        (
            while true; do
                URL=$(yt-dlp -f best -g "$LINK" 2>/dev/null)
                [ -z "$URL" ] && sleep 5 && continue

                ffmpeg -re -i "$URL" \
                    -reconnect 1 \
                    -reconnect_streamed 1 \
                    -reconnect_delay_max 5 \
                    -c:v copy -c:a aac \
                    -f hls -hls_time 10 -hls_list_size 0 \
                    "$OUTPUT"

                sleep 2
            done
        ) >/dev/null 2>&1 &

    # Arquivo local
    else
        if [ ! -f "$LINK" ]; then
            echo "Arquivo não encontrado!"
            return
        fi

        ffmpeg -stream_loop -1 -re -i "$LINK" \
            -c:v copy -c:a aac \
            -f hls -hls_time 10 -hls_list_size 0 \
            "$OUTPUT" >/dev/null 2>&1 &
    fi

    STREAMS_PID["$NAME"]=$!
    STREAM_HISTORY["$NAME"]="STARTED"

    echo "Stream '$NAME' iniciada (PID ${STREAMS_PID[$NAME]})"
}

# -------------------------
# Start stream existente
# -------------------------
start_stream() {
    read NAME
    OUTPUT="$STREAM_DIR/$NAME.m3u8"

    if [ ! -f "$OUTPUT" ]; then
        echo "Stream não encontrada!"
        return
    fi

    ffmpeg -re -i "$OUTPUT" -c copy -f hls -hls_time 10 -hls_list_size 0 "$OUTPUT" \
        >/dev/null 2>&1 &

    STREAMS_PID["$NAME"]=$!
    STREAM_HISTORY["$NAME"]="STARTED"
}

# -------------------------
# Stop stream
# -------------------------
stop_stream() {
    read -rp "Nome do canal: " NAME

    PID="${STREAMS_PID[$NAME]:-}"

    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null
        unset STREAMS_PID["$NAME"]
        STREAM_HISTORY["$NAME"]="STOPPED"
        echo "Stream '$NAME' parada."
    fi
}

# -------------------------
# Exportar M3U
# -------------------------
export_m3u() {
    M3U="$BASE_DIR/playlist.m3u"

    echo "#EXTM3U" > "$M3U"

    for FILE in "$STREAM_DIR"/*.m3u8; do
        [ -f "$FILE" ] || continue
        NAME=$(basename "$FILE" .m3u8)
        echo "#EXTINF:-1,$NAME" >> "$M3U"
        echo "$FILE" >> "$M3U"
    done

    echo "Playlist exportada: $M3U"
}

# -------------------------
# Histórico
# -------------------------
history_streams() {
    echo "===== HISTÓRICO ====="
    for NAME in "${!STREAM_HISTORY[@]}"; do
        echo "$NAME : ${STREAM_HISTORY[$NAME]}"
    done
}

# -------------------------
# Agendamento
# -------------------------
schedule_stream() {
    read -rp "Nome do canal: " NAME
    read -rp "Hora start (HH:MM): " HSTART
    read -rp "Hora stop (HH:MM): " HSTOP

    echo "$HSTART $NAME start" >> "$SCHEDULE_FILE"
    echo "$HSTOP $NAME stop" >> "$SCHEDULE_FILE"

    echo "Agendamento criado."
}

process_schedule() {
    NOW=$(date +%H:%M)

    while read -r TIME NAME ACTION; do
        [ "$TIME" = "$NOW" ] || continue

        if [ "$ACTION" = "start" ]; then
            start_stream <<< "$NAME"
        elif [ "$ACTION" = "stop" ]; then
            stop_stream <<< "$NAME"
        fi
    done < "$SCHEDULE_FILE"
}

# -------------------------
# Menu
# -------------------------
menu() {
    while true; do
        monitor_alerts
        process_schedule

        echo
        echo "===== STREAM MANAGER 24/7 ====="
        echo "1) Adicionar stream"
        echo "2) Start stream"
        echo "3) Stop stream"
        echo "4) Dashboard"
        echo "5) Exportar M3U"
        echo "6) Histórico"
        echo "7) Agendar"
        echo "0) Sair"
        read -rp "Opção: " OP

        case "$OP" in
            1) add_stream ;;
            2) start_stream ;;
            3) stop_stream ;;
            4) dashboard ;;
            5) export_m3u ;;
            6) history_streams ;;
            7) schedule_stream ;;
            0) exit 0 ;;
            *) echo "Opção inválida!" ;;
        esac
    done
}

menu