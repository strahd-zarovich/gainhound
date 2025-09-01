#!/bin/bash
set -e

LOG_FILE="/data/logs/normalize.log"
echo "[$(date '+%H:%M:%S')] [NORMALIZE] Starting normalization at $(date)" >> "$LOG_FILE"

source /data/config.conf

# Skip if disabled
if [[ "$RUN_GAIN_CHECK" != "true" ]]; then
    echo "[$(date '+%H:%M:%S')] [NORMALIZE] RUN_GAIN_CHECK is false — skipping." >> "$LOG_FILE"
    exit 0
fi

# Ensure processed list exists
PROCESSED_LIST="/data/processed.list"
mkdir -p /data
touch "$PROCESSED_LIST"

# Find all MP3 files not yet processed
find /music -type f -iname "*.mp3" | while read -r FILE; do
    if grep -Fxq "$FILE" "$PROCESSED_LIST"; then
        echo "[$(date '+%H:%M:%S')] [NORMALIZE] Skipping (already processed): $FILE" >> "$LOG_FILE"
        continue
    fi

    echo "[$(date '+%H:%M:%S')] [NORMALIZE] Checking gain: $FILE" >> "$LOG_FILE"
    gain_output=$(mp3gain -s c -o -q "$FILE" 2>&1)
    echo "[$(date '+%H:%M:%S')] [NORMALIZE] Output: $gain_output" >> "$LOG_FILE"

    echo "$FILE" >> "$PROCESSED_LIST"
done

echo "[$(date '+%H:%M:%S')] [NORMALIZE] Normalization completed at $(date)" >> "$LOG_FILE"
