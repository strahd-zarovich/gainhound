#!/usr/bin/env bash
# ==============================================================================
# File:        log_rotate.sh
# Purpose:     Rotate and retain Gainhound logs to prevent unbounded growth.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior
#   • For each known log in /data/logs:
#       - If present and non-empty, gzip the current file to <name>.<YYYYMMDD>.gz
#         and then truncate the live file.
#   • Deletes .gz archives older than LOG_RETENTION_DAYS.
#   • Writes a summary to /data/logs/log_rotate.log (and stdout).
#
# Logging
#   • Every line starts with "[HH:MM:SS]".
#   • High-level messages go to stdout and to /data/logs/log_rotate.log.
#
# Inputs (env or /data/config.conf via source)
#   LOG_RETENTION_DAYS  : How many days of archives to keep (default: 14)
#
# Notes
#   • Rotation is date-based (daily). Run via cron (see setup_cron.sh).
#   • Safe no-op if logs are missing or already empty.
# ==============================================================================

set -Eeo pipefail

ts() { printf "[%s]" "$(date '+%Y-%m-%d %H:%M:%S')"; }
log() { echo "$(ts) [LOGROTATE] $*"; echo "$(ts) [LOGROTATE] $*" >> /data/logs/log_rotate.log 2>/dev/null || true; }

# Optional config (best-effort)
if [[ -f /data/config.conf ]]; then
  # shellcheck source=/dev/null
  source /data/config.conf
fi

: "${LOG_RETENTION_DAYS:=14}"

LOG_DIR="/data/logs"
DATE_STAMP="$(date +'%Y%m%d')"

# Known logs to rotate (extend as needed)
LOGS=(
  "gainhound.log"
  "gain_check.log"
  "integrity_check.log"
  "reencode_gain.log"
  "watch_music.log"
  "cron_gainhound.log"
  "cron_plex.log"
  "cron_setup.log"
  "fix_permissions.log"
  "log_rotate.log"        # yes, we rotate our own previous content too
)

log "--- Rotation started ---"
mkdir -p "${LOG_DIR}" || true

for name in "${LOGS[@]}"; do
  src="${LOG_DIR}/${name}"
  if [[ -s "${src}" ]]; then
    dst="${src}.${DATE_STAMP}.gz"
    log "Rotating: ${name} → $(basename "${dst}")"
    # Gzip to YYYYMMDD.gz (keep original timestamps in archive metadata)
    gzip -c -- "${src}" > "${dst}" 2>/dev/null || {
      log "WARN: gzip failed for ${name}; skipping."
      continue
    }
    # Truncate live log after successful archive
    : > "${src}" || log "WARN: failed to truncate ${name}"
  else
    # Silent skip if file missing or empty; uncomment if you want a log line
    # log "Skip (missing/empty): ${name}"
    :
  fi
done

# Retention: delete archived .gz older than LOG_RETENTION_DAYS
if [[ "${LOG_RETENTION_DAYS}" -gt 0 ]]; then
  log "Pruning .gz older than ${LOG_RETENTION_DAYS} day(s)"
  find "${LOG_DIR}" -type f -name "*.gz" -mtime +"${LOG_RETENTION_DAYS}" -print -delete 2>/dev/null \
    | while read -r removed; do
        log "Deleted: $(basename "${removed}")"
      done
fi

log "--- Rotation finished ---"
