#!/bin/bash
#
#
#  00 5 * * *      root    /opt/influxdb-backup/influxdb-backup.sh
#
########################################

BACKUP_DESTINATION_DIR="/mnt/backup/influxdb-backups"
BACKUP_TMP_ROOT_DIR="/mnt/backup/tmp/influxback."
INFLUXD="/usr/bin/influxd"
INFLUX_DB="home_assistant"
INFLUX_RP=""
awk=gawk

#########################################

TMP_NOW=$(date +"%Y%m%d%H%M%S%3N")
BACKUP_TMP_DIR="${BACKUP_TMP_ROOT_DIR}${TMP_NOW}"
TARGET_BACKUP_FILE="${BACKUP_DESTINATION_DIR}/${TMP_NOW}.tar.xz"

trap do_cleanup_signal SIGHUP SIGINT SIGTERM


stamp() {
  echo $(date +"%Y-%m-%d %T.%3N")
}


do_cleanup_signal() {
  do_cleanup_exit 1 "Received kill signal"
}

log() {
  echo "[$(stamp)] $1"
}

get_human_read_size() {
  if [ "$1" = "" ]; then
    echo "0 B"
  elif [ "$awk" = '' ] || [ ! -x "$(which $awk)" ]; then
    echo "$1 B"
  else
    echo $($awk -v sum=$1 'BEGIN{
        hum[1024**3]="Gb";hum[1024**2]="Mb";hum[1024]="Kb";
        for (x=1024**3; x>=1024; x/=1024){
          if (sum>=x) { printf "%.2f %s\n",sum/x,hum[x];break }
        }}')

  fi
}


do_cleanup_exit() {

  if [ "$2" != "" ]; then
    log "$2"
  else
    log "Cleaning up"
  fi

  if [ -d "$BACKUP_TMP_DIR" ]; then
    rm -rf "$BACKUP_TMP_DIR"
  fi

  if [ "$1" = "" ]; then
    exit 0
  else
    exit "$1"
  fi
}


if [ ! -x "$INFLUXD" ]; then
  log "Didn't find influxd. Aborting"
  do_cleanup_exit 1
fi

[ "$INFLUX_DB" = "" ] && do_cleanup_exit 1 "Database name cannot be empty"
[ -e "$TARGET_BACKUP_FILE" ] && do_cleanup_exit 1 "Target destination file already exists"

mkdir -p "$BACKUP_TMP_DIR" || do_cleanup_exit 1 "Error Creating temporary dir"
mkdir -p "$BACKUP_DESTINATION_DIR" || do_cleanup_exit 1 "Error Creating destination dir"

log "Using temporary backup dir: $BACKUP_TMP_DIR"


for db in "$INFLUX_DB"; do
  log "Backing influxdb: $db"

  if [ "$INFLUX_RP" = "" ]; then
    eval $INFLUXD backup -portable -database "$INFLUX_DB" "$BACKUP_TMP_DIR" >/dev/null || do_cleanup_exit 1 "Error Creating backup"
  else

    for rp in $INFLUX_RP; do
      log "Backing rp: $rp"
      eval $INFLUXD backup -portable -database "$INFLUX_DB" -retention "$rp"  "$BACKUP_TMP_DIR" >/dev/null || do_cleanup_exit 1 "Error Creating backup for rp: $rp"
    done
  fi
done

log "Compressing to file: $TARGET_BACKUP_FILE"

pushd "$BACKUP_TMP_DIR" >/dev/null

tar cJf "$TARGET_BACKUP_FILE" *
ret_code=$?

popd >/dev/null

[ $ret_code -eq 0 ] || do_cleanup_exit 1 "Error compressing backup"

compressed_size_bytes=$(stat -c "%s" "$TARGET_BACKUP_FILE")
compressed_size=$(get_human_read_size "$compressed_size_bytes")
log "Compressed filesize is: ${compressed_size}"


do_cleanup_exit

