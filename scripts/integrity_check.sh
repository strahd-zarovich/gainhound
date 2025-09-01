#!/usr/bin/env bash
# ==============================================================================
# File:        integrity_check.sh
# Purpose:     Validate MP3 file integrity using ffprobe. Record failures.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior
#   • Scans MUSIC_DIR recursively for *.mp3 (case-insensitive).
#   • Runs ffprobe in error-only mode; any non-zero exit indicates a problem.
#   • Per-file details go ONLY to this script’s logfile (not stdout).
#   • Appends failures to processed.list with a status marker "integrity=FAIL".
#
# Logging
#   • High-level messages → stdout + file via log().
#   • Per-file messages   → file-only via log_file_only(), never stdout.
#   • This script ALWAYS logs to /data/logs/integrity_check.log.
#
# Inputs (via /data/config.conf or environment)
#   MUSIC_DIR          : Root of music library (you’re using /music)
#   PROCESSED_LIST     : Output index for recording failures
#
# Notes
#   • We only append FAIL cases to processed.list to keep the file lean.
#   • ffprobe must be present in the image (part of ffmpeg packages).
# ==============================================================================

set -Eeo pipefail

# --- Logging setup (force a dedicated logfile for this script) -----------------
LOG_TAG="INTEGRITY"
LOG_FILE="/data/logs/integrity_check.log"

# Shared helpers
source /scripts/common.sh

log INFO "--- Run started ---"
load_config

if [[ ! -d "${MUSIC_DIR}" ]]; then
  log WARN "MUSIC_DIR does not exist: ${MUSIC_DIR} (nothing to do)"
  log INFO "--- Run finished (no directory) ---"
  exit 0
fi
mkdir -p "$(dirname -- "${PROCESSED_LIST}")"

# Counters
files_ok=0
files_fail=0
files_skipped=0

# Function: check a single file with ffprobe
check_file() {
  local f="$1"
  # Quiet probe: errors only. We don't want stdout spam; capture stderr for logging if needed.
  # Two common forms; we use show_format/show_streams to force a parse without output.
  set +e
  ffprobe -v error -hide_banner -show_format -show_streams -- "${f}" > /dev/null 2>&1
  rc=$?
  set -e
  return ${rc}
}

# NUL-safe iteration
while IFS= read -r -d '' file; do
  # Per-file logs go ONLY to the integrity log
  log_file_only INFO "Probing: ${file}"

  if check_file "${file}"; then
    ((files_ok++)) || true
    log_file_only INFO "OK: ${file}"
  else
    ((files_fail++)) || true
    log_file_only ERROR "FAIL (ffprobe error): ${file}"
    # Append only failures to processed.list with a clear marker
    printf "%s\t%s\t%s\n" "$(date +'%Y-%m-%dT%H:%M:%S')" "${file}" "integrity=FAIL" >> "${PROCESSED_LIST}"
  fi
done < <(find "${MUSIC_DIR}" -type f -iname '*.mp3' -print0)

log INFO "Summary: ok=${files_ok}, fail=${files_fail}, skipped=${files_skipped}"
log INFO "--- Run finished ---"
