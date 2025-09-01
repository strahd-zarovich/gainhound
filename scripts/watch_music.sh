#!/usr/bin/env bash
# ==============================================================================
# File:        watch_music.sh
# Purpose:     Watch MUSIC_DIR for changes and trigger run_gainhound.sh
#              with simple debouncing and lock awareness.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior
#   • Loads /data/config.conf and common defaults.
#   • Uses inotifywait (if present) to monitor create/move/close_write events
#     under MUSIC_DIR (recursive). Falls back to lightweight polling if missing.
#   • Debounces rapid bursts using a cooldown window before triggering.
#   • Respects the unified lock (/data/gainhound.lock) to avoid overlaps.
#
# Logging
#   • Timestamped lines via common.sh log(): "[HH:MM:SS] [WATCH] [LEVEL] ..."
#   • File log: /data/logs/watch_music.log (unless overridden via LOG_FILE env).
#
# Inputs (from /data/config.conf or env)
#   MUSIC_DIR           : directory to watch
#   WATCH_COOLDOWN_SECS : minimum seconds between triggers (default 60)
#   WATCH_POLL_SECS     : poll interval if inotifywait not available (default 30)
#
# Failure Modes & Safeguards
#   • Missing MUSIC_DIR → WARN and exit 0 (no-op).
#   • If inotifywait is absent, logs WARN once and switches to polling.
#   • If lock exists when a trigger fires, skip and wait for next event.
# ==============================================================================

set -Eeo pipefail

LOG_TAG="WATCH"
LOG_FILE="${LOG_FILE:-/data/logs/watch_music.log}"
source /scripts/common.sh
load_config

# Defaults / tuning knobs
: "${WATCH_COOLDOWN_SECS:=60}"
: "${WATCH_POLL_SECS:=30}"

# State files
LAST_RUN_FILE="/data/.watch.last_run"

if [[ ! -d "${MUSIC_DIR}" ]]; then
  log WARN "MUSIC_DIR does not exist: ${MUSIC_DIR} (watcher exiting)"
  exit 0
fi

log INFO "Starting watcher on: ${MUSIC_DIR} (cooldown=${WATCH_COOLDOWN_SECS}s)"

# Returns 0 if enough time has passed since the last run (or file missing)
cooldown_ok() {
  local now last=0
  now="$(date +%s)"
  if [[ -f "${LAST_RUN_FILE}" ]]; then
    last="$(cat "${LAST_RUN_FILE}" 2>/dev/null || echo 0)"
  fi
  # If now - last >= cooldown → OK
  if (( now - last >= WATCH_COOLDOWN_SECS )); then
    return 0
  fi
  return 1
}

mark_run() {
  date +%s > "${LAST_RUN_FILE}" 2>/dev/null || true
}

trigger_run() {
  # Respect lock: if a run is in progress, skip this trigger
  if [[ -e "${GAINHOUND_LOCK}" ]]; then
    log INFO "Lock present; skipping trigger."
    return 0
  fi
  if cooldown_ok; then
    log INFO "Change detected → starting run_gainhound.sh"
    mark_run
    /scripts/run_gainhound.sh
  else
    log INFO "Change detected but within cooldown; skipping."
  fi
}

# ----------------------- inotify-based Watcher -------------------------------
if command -v inotifywait >/dev/null 2>&1; then
  # We watch for events that indicate a file is newly created or finished writing
  #   close_write : a file was closed after being opened for writing
  #   moved_to    : a file was moved into the directory
  #   create      : a file/directory was created
  log INFO "inotifywait found; using event-based watch."
  # Run forever; filter for .mp3 files case-insensitively in userland
  inotifywait -m -r -e close_write -e moved_to -e create --format '%w%f' --quiet "${MUSIC_DIR}" \
  | while IFS= read -r path; do
      # Only react to mp3s
      case "${path,,}" in
        *.mp3)
          log INFO "Event: ${path}"
          trigger_run
          ;;
        *)
          # Ignore non-mp3 changes to reduce noise
          ;;
      esac
    done

# ------------------------ Polling Fallback -----------------------------------
else
  log WARN "inotifywait not available; falling back to polling (interval=${WATCH_POLL_SECS}s)."
  # Create a baseline snapshot timestamp
  SNAP_FILE="/data/.watch.snapshot"
  : > "${SNAP_FILE}" || true
  touch -d '1970-01-02' "${SNAP_FILE}" 2>/dev/null || true

  while true; do
    # Find any mp3 newer than the last snapshot
    changed=false
    while IFS= read -r -d '' f; do
      log INFO "Detected new/updated file: ${f}"
      changed=true
      # break after first detection to debounce via cooldown/trigger
      break
    done < <(find "${MUSIC_DIR}" -type f -iname '*.mp3' -newer "${SNAP_FILE}" -print0)

    if [[ "${changed}" == true ]]; then
      trigger_run
      # Refresh snapshot time to "now" after a trigger
      : > "${SNAP_FILE}" || true
    fi
    sleep "${WATCH_POLL_SECS}"
  done
fi
