#!/usr/bin/env bash
set -Eeo pipefail

ts() { printf "[%s]" "$(date '+%Y-%m-%d %H:%M:%S')"; }
log() { echo "$(ts) [PLEX] $*"; echo "$(ts) [PLEX] $*" >> /data/logs/plex_analyze.log 2>&1 || true; }

CONFIG_FILE="/data/config.conf"
[[ -f "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

# Export what Python needs
export PLEX_URL PLEX_TOKEN

# Default to per-item mode unless explicitly set otherwise
export PLEX_ANALYZE_MODE="${PLEX_ANALYZE_MODE:-items}"

log "Starting Plex library analysis at $(date)"

set +e
/usr/bin/env python3 /scripts/force_plex_analyze.py >/dev/null 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  log "ERROR: Plex library analysis failed with code ${rc} at $(date)"
  exit $rc
fi

log "Plex library analysis completed successfully at $(date)"
