#!/usr/bin/env bash
# ==============================================================================
# File:        reencode.sh
# Purpose:     Thin runner that prepares logging/env and launches reencode_gain.py
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior:
#   • Ensures /data/logs exists (prevents 'No such file or directory' on redirect)
#   • Sources /data/config.conf (if present) and exports key env vars
#   • Verifies required tools (python3, ffmpeg, mp3gain)
#   • Starts a timestamped run and launches the Python re-encode worker
#   • DOES NOT redirect Python stdout into the same log to avoid duplicate lines
# Logging:
#   • High-level start/end go to Docker stdout
#   • Detailed per-file logs are written by reencode_gain.py -> /data/logs/reencode_gain.log
# ==============================================================================

set -Eeo pipefail

ts() { printf "[%s]" "$(date '+%Y-%m-%d %H:%M:%S')"; }
log() { echo "$(ts) [REENCODE] $*"; }

# --- Paths --------------------------------------------------------------------
LOG_DIR="/data/logs"
LOG_FILE="${LOG_DIR}/reencode_gain.log"
CONFIG_FILE="/data/config.conf"

# --- Ensure log dir exists BEFORE any script writes there ---------------------
mkdir -p "${LOG_DIR}"

# --- Load config (optional) ---------------------------------------------------
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

# --- Defaults for Python worker ----------------------------------------------
export MUSIC_DIR="${MUSIC_DIR:-/music}"
export GAIN_THRESHOLD="${GAIN_THRESHOLD:-5}"
export LOG_DIR="${LOG_DIR}"
# Optional knobs (used by Python if set): FFMPEG_VBR_QUALITY, ID3_VERSION, MAX_FILES, DRY_RUN

# --- Preflight checks ---------------------------------------------------------
need=0
command -v python3 >/dev/null 2>&1 || { log "[ERROR] python3 not found"; need=1; }
command -v ffmpeg  >/dev/null 2>&1 || { log "[ERROR] ffmpeg not found";  need=1; }
command -v mp3gain >/dev/null 2>&1 || { log "[ERROR] mp3gain not found"; need=1; }
if [[ $need -ne 0 ]]; then
  log "[ERROR] Missing required tools; aborting."
  exit 127
fi

# Create the log file if missing (do not write repeated headers to avoid noise)
if [[ ! -f "${LOG_FILE}" ]]; then
  : > "${LOG_FILE}"
fi

log "Starting re-encode run (threshold=${GAIN_THRESHOLD} dB, dir=${MUSIC_DIR})"
# NOTE: Do NOT append Python stdout to LOG_FILE; the Python script writes to it directly.
set +e
/usr/bin/env python3 /scripts/reencode_gain.py
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  log "Completed with errors (rc=${rc}) — see ${LOG_FILE}"
  exit $rc
fi
log "Completed successfully — see ${LOG_FILE}"
