#!/bin/bash
# ============================================================================
# Script: undo_gain.sh
# Purpose: Undo any gain adjustments made by mp3gain by reverting changes.
# Author: Gainhound Project
# Created: 2025-08-24
# ============================================================================
set -e

LOCK_FILE="/data/gainhound.lock"
LOG_FILE="/data/logs/undo_gain.log"
PROCESSED_LIST="/data/processed.list"
MUSIC_DIR="/music"

echo "[$(date '+%H:%M:%S')] [UNDO] Starting gain undo process..." | tee -a "$LOG_FILE"

# Prevent multiple instances
if [[ -f "$LOCK_FILE" ]]; then
    echo "[$(date '+%H:%M:%S')] [UNDO] Lock file exists. Another instance is running. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

touch "$LOCK_FILE"
mkdir -p /data/logs
touch "$LOG_FILE"

# Find and undo gain changes
find "$MUSIC_DIR" -type f -name "*.mp3" | while read -r mp3; do
    echo "[$(date '+%H:%M:%S')] [UNDO] Reverting gain on: $mp3" | tee -a "$LOG_FILE"
    mp3gain -s c -u "$mp3" >> "$LOG_FILE" 2>&1
done

# Clear processed list
if [[ -f "$PROCESSED_LIST" ]]; then
    echo "[$(date '+%H:%M:%S')] [UNDO] Clearing processed list: $PROCESSED_LIST" | tee -a "$LOG_FILE"
    > "$PROCESSED_LIST"
fi

echo "[$(date '+%H:%M:%S')] [UNDO] Undo process complete." | tee -a "$LOG_FILE"
rm -f "$LOCK_FILE"
