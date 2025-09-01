#!/usr/bin/env bash
# ==============================================================================
# File:        run_gainhound.sh
# Purpose:     Orchestrate a single Gainhound cycle. Respects feature toggles:
#              RUN_GAIN_CHECK, RUN_INTEGRITY_CHECK, RUN_REENCODE_FOR_GAIN.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior
#   • Loads /data/config.conf and common defaults.
#   • Uses a unified lock (/data/gainhound.lock) to prevent overlapping runs.
#   • Conditionally invokes:
#       - /scripts/gain_check.sh
#       - /scripts/integrity_check.sh
#       - /scripts/reencode_gain.py (Python)
#   • Logs a concise start/finish summary with durations.
#
# Logging
#   • Timestamped lines via common.sh log(): "[HH:MM:SS] [GAINHOUND] [LEVEL] ..."
#   • File log: /data/logs/gainhound.log (unless overridden via LOG_FILE env).
#
# Inputs (from /data/config.conf or env)
#   RUN_GAIN_CHECK          : true/false
#   RUN_INTEGRITY_CHECK     : true/false
#   RUN_REENCODE_FOR_GAIN   : true/false
#   MUSIC_DIR               : music root (e.g., /data/music or /music)
#   GAIN_THRESHOLD          : dB threshold passed through to re-encode stage
#
# Failure Modes & Safeguards
#   • If lock exists, logs WARN and exits 0 (no-op).
#   • Each sub-step failure is logged as ERROR, but the orchestrator continues
#     to the next enabled step to avoid blocking other work.
#   • Lock is removed on exit (trap).
# ==============================================================================

set -Eeo pipefail

LOG_TAG="GAINHOUND"
LOG_FILE="${LOG_FILE:-/data/logs/gainhound.log}"
source /scripts/common.sh
load_config

start_epoch="$(date +%s)"
log INFO "Starting Gainhound cycle..."

# ------------------------------ Locking ---------------------------------------
acquire_lock() {
  if [[ -e "${GAINHOUND_LOCK}" ]]; then
    log WARN "Lock exists (${GAINHOUND_LOCK}); another run is active. Skipping."
    exit 0
  fi
  # Best-effort lock create
  echo "$$" > "${GAINHOUND_LOCK}" 2>/dev/null || true
  log INFO "Acquired lock: ${GAINHOUND_LOCK}"
}

release_lock() {
  if [[ -e "${GAINHOUND_LOCK}" ]]; then
    rm -f "${GAINHOUND_LOCK}" 2>/dev/null || true
    log INFO "Released lock: ${GAINHOUND_LOCK}"
  fi
}

trap 'release_lock' EXIT

acquire_lock

# --------------------------- Feature Toggles -----------------------------------
: "${RUN_GAIN_CHECK:=false}"
: "${RUN_INTEGRITY_CHECK:=false}"
: "${RUN_REENCODE_FOR_GAIN:=false}"

# ------------------------------ Steps -----------------------------------------

# 1) Gain check
if bool "${RUN_GAIN_CHECK}"; then
  log INFO "Running gain_check.sh..."
  set +e
  /scripts/gain_check.sh
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    log ERROR "gain_check.sh exited with code ${rc}"
  else
    log INFO "gain_check.sh completed."
  fi
else
  log INFO "RUN_GAIN_CHECK disabled; skipping."
fi

# 2) Integrity check
if bool "${RUN_INTEGRITY_CHECK}"; then
  log INFO "Running integrity_check.sh..."
  if [[ ! -x "/scripts/integrity_check.sh" ]]; then
    log ERROR "integrity_check.sh not found or not executable; skipping."
  else
    set +e
    /scripts/integrity_check.sh
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      log ERROR "integrity_check.sh exited with code ${rc}"
    else
      log INFO "integrity_check.sh completed."
    fi
  fi
else
  log INFO "RUN_INTEGRITY_CHECK disabled; skipping."
fi

# 3) Re-encode for high gain delta (Python)
if bool "${RUN_REENCODE_FOR_GAIN}"; then
  log INFO "Running reencode_gain.py (threshold=${GAIN_THRESHOLD}, music_dir=${MUSIC_DIR})..."
  if [[ ! -f "/scripts/reencode_gain.py" ]]; then
    log ERROR "reencode_gain.py not found; skipping."
  else
    # Pass key settings via env so the script can read them consistently.
    set +e
    MUSIC_DIR="${MUSIC_DIR}" GAIN_THRESHOLD="${GAIN_THRESHOLD}" python3 /scripts/reencode_gain.py
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      log ERROR "reencode_gain.py exited with code ${rc}"
    else
      log INFO "reencode_gain.py completed."
    fi
  fi
else
  log INFO "RUN_REENCODE_FOR_GAIN disabled; skipping."
fi

# ------------------------------ Summary ---------------------------------------
end_epoch="$(date +%s)"
elapsed="$(( end_epoch - start_epoch ))"
log INFO "Gainhound cycle finished in ${elapsed}s."
