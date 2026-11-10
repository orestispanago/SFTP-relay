#!/bin/sh
# Moves files received over SFTP to an FTP server, then removes emptied folders.
# Skips files and folders changed in the last 5 min (still uploading).

DIR=$(dirname "$(readlink -f "$0")")
LOG="$DIR/logs/relay.log"
MAX_LOG_BYTES=1000000

mkdir -p "$DIR/logs"
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt "$MAX_LOG_BYTES" ]; then
    mv "$LOG" "$LOG.1"
fi
exec >> "$LOG" 2>&1

. "$DIR/.env"
export LFTP_PASSWORD="$FTP_PASS"

echo "$(date -u +%FT%TZ) start"
if lftp --env-password -u "$FTP_USER" \
    -e "mirror -R --Remove-source-files --older-than=now-5minutes $SRC_DIR $DST_DIR; quit" \
    "$FTP_IP"; then
    find "$SRC_DIR" -mindepth 1 -type d -empty -mmin +5 -delete
    echo "$(date -u +%FT%TZ) done"
else
    echo "$(date -u +%FT%TZ) lftp failed, files kept for the next run"
fi
