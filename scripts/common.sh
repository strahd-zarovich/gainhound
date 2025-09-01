#!/usr/bin/env bash
# ==============================================================================
# File:        common.sh
# Purpose:     Shared utilities for Gainhound shell scripts.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# What this provides
#   • log()           : Timestamped logging to stdout and optional file.
#   • log_file_only() : Timestamped logging ONLY to file (never stdout).
#   • load_config()   : Loads /data/config.conf (or a specified file) safely.
#   • bool()          : Interprets common boolean strings as 0/1 for conditionals.
#   • default vars    : Safe defaults for key paths & thresholds.
#
# Conventions
#   • Every log line starts with a time prefix "[HH:MM:SS]".
#   • Scripts should source this file:  source /scripts/common.sh
#   • To enable file logging, set LOG_FILE before calling log().
#
# Assumptions / Requirements
#   • bash 4+, coreutils, awk available in the container.
#   • /data is the persistent volume mount.
#
# Failure Modes
#   • If config cannot be loaded, defaults are used and a WARN is logged.
#   • If LOG_FILE cannot be written, logging continues to stdout (for log()).
# ==============================================================================

set -Eeo pipefail

# ------------------------------ Defaults --------------------------------------

: "${CONFIG_FILE:=/data/config.conf}"
: "${MUSIC_DIR:=/data/music}"
: "${PROCESSED_LIST:=/data/processed.list}"
: "${GAINHOUND_LOCK:=/data/gainhound.lock}"
: "${GAIN_THRESHOLD:=5}"
: "${LOG_FILE:=}"
: "${LOG_TAG:=COMMON}"

# ----------------------------- Logging ----------------------------------------

# log LEVEL MESSAGE...
#   Writes to stdout and, if set, to LOG_FILE.
log() {
  local level="$1"; shift || true
  local ts="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local tag="[$LOG_TAG]"
  local msg="$*"
  # stdout
  echo "${ts} ${tag} [${level}] ${msg}"
  # file (best-effort)
  if [[ -n "${LOG_FILE}" ]]; then
    mkdir -p "$(dirname -- "${LOG_FILE}")" 2>/dev/null || true
    echo "${ts} ${tag} [${level}] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
  fi
}

# log_file_only LEVEL MESSAGE...
#   NEVER writes to stdout; only to LOG_FILE (if defined).
#   If LOG_FILE is not set, it silently discards the message.
log_file_only() {
  local level="$1"; shift || true
  [[ -z "${LOG_FILE}" ]] && return 0
  local ts="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local tag="[$LOG_TAG]"
  local msg="$*"
  mkdir -p "$(dirname -- "${LOG_FILE}")" 2>/dev/null || true
  echo "${ts} ${tag} [${level}] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

# ---------------------------- Config Loader -----------------------------------

load_config() {
  local cfg="${1:-${CONFIG_FILE}}"
  if [[ -f "${cfg}" ]]; then
    # shellcheck source=/dev/null
    source "${cfg}"
    log INFO "Loaded config: ${cfg}"
  else
    log WARN "Config not found, using defaults: ${cfg}"
  fi
}

# ----------------------------- Bool Helper ------------------------------------

bool() {
  local v="${1:-}"
  shopt -s nocasematch
  case "${v}" in
    1|true|yes|on|enable|enabled) return 0 ;;
    *)                             return 1 ;;
  esac
}
