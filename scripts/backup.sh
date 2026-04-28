#!/usr/bin/env bash
# SIEMBA Backup Script
# Usage: sudo bash backup.sh [/path/to/backup/dir]
set -euo pipefail

BACKUP_DIR="${1:-/opt/siemba-backups}"
DATE=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/siemba-backup-$DATE"
LOG="/tmp/siemba-backup.log"
GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[BACKUP]${NC} $*" | tee -a "$LOG"; }

mkdir -p "$DEST"

log "Backing up SIEMBA configs..."
cp -r /opt/siemba/config "$DEST/config" 2>/dev/null || true
cp /opt/siemba/.env "$DEST/.env.backup" 2>/dev/null || true
cp /opt/siemba/.credentials "$DEST/.credentials.backup" 2>/dev/null || true

log "Backing up Elasticsearch indices..."
curl -sf -X PUT "http://localhost:9200/_snapshot/siemba_backup" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"fs\",\"settings\":{\"location\":\"$DEST/elasticsearch\"}}" >> "$LOG" 2>&1 || true
curl -sf -X PUT "http://localhost:9200/_snapshot/siemba_backup/snapshot_$DATE?wait_for_completion=true" \
  >> "$LOG" 2>&1 || log "ES snapshot skipped (may not be running)"

log "Backing up Grafana..."
cp -r /var/lib/grafana "$DEST/grafana" 2>/dev/null || true

log "Compressing backup..."
tar -czf "$BACKUP_DIR/siemba-backup-$DATE.tar.gz" -C "$BACKUP_DIR" "siemba-backup-$DATE"
rm -rf "$DEST"

# Keep only last 7 backups
ls -t "$BACKUP_DIR"/siemba-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true

SIZE=$(du -sh "$BACKUP_DIR/siemba-backup-$DATE.tar.gz" | cut -f1)
log "Backup complete: $BACKUP_DIR/siemba-backup-$DATE.tar.gz ($SIZE)"
