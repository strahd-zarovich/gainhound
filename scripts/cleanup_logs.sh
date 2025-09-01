#!/bin/bash
set -e

LOG_DIR="/data/logs"
RETENTION_DAYS=5
LOG_FILE="$LOG_DIR/log_cleanup.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CLEANUP_LOGS] Starting log cleanup at $(date)" >> "$LOG_FILE"
find "$LOG_DIR" -type f -name "*.log*" -mtime +$RETENTION_DAYS -print -delete >> "$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CLEANUP_LOGS] Cleanup complete at $(date)" >> "$LOG_FILE"
