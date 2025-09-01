#!/usr/bin/env bash
# ==============================================================================
# File:        gain_check.sh
# Purpose:     Analyze MP3 files with mp3gain, parse dB gain (TSV output),
#              and append clean results to /data/processed.list.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior
#   • Scans MUSIC_DIR recursively for *.mp3 (case-insensitive).
#   • Parses mp3gain TSV "dB gain" column.
#   • Records successful parses to processed.list (timestamp, path, dB).
#   • Per-file details go ONLY to this script’s logfile (not stdout).
#
# Logging
#   • High-level messages → stdout + file via log().
#   • Per-file messages   → file-only via log_file_only(), never stdout.
#   • This script ALWAYS logs to /data/logs/gain_check.log (independent of
#     whatever LOG_FILE the parent orchestrator uses).
#
# Inputs (via /data/config.conf or environment)
#   MUSIC_DIR          : Root of music library (you’re using /music)
#   PROCESSED_LIST     : Output index for successful parses
#   GAIN_THRESHOLD     : dB threshold for informational comparison
#
# Notes
#   • We honor MUSIC_DIR as configured (no path rewrites).
#   • processed.list grows only on successful parses.
#   • mp3gain must be present in the image.
# ==============================================================================

set -Eeo pipefail

# --- Logging setup (force a dedicated logfile for this script) -----------------
LOG_TAG="GAIN_CHECK"
LOG_FILE="/data/logs/gain_check.log"

# Shared helpers (provides log(), log_file_only(), load_config(), etc.)
source /scripts/common.sh

log INFO "--- Run started ---"
load_config

# Ensure output directory for processed list exists
if [[ ! -d "${MUSIC_DIR}" ]]; then
  log WARN "MUSIC_DIR does not exist: ${MUSIC_DIR} (nothing to do)"
  log INFO "--- Run finished (no directory) ---"
  exit 0
fi
mkdir -p "$(dirname -- "${PROCESSED_LIST}")"

# --- Helper: parse numeric dB gain from mp3gain TSV (with loose fallback) -----
parse_db_gain() {
  local __outvar="$1"; shift
  local tsv="$*"
  local val=""
  # Primary: tab-separated with header "File    MP3 gain    dB gain ..."
  val="$(LC_ALL=C awk -F'\t' '
    BEGIN { found=0 }
    NR==1 && $1=="File" { next }     # skip header
    NF>=3 { print $3; found=1; exit }
    END { if (!found) exit 1 }
  ' <<< "${tsv}" 2>/dev/null)" || true

  # Fallback: loose grep for “dB gain” then first numeric
  if [[ -z "${val}" ]]; then
    val="$(LC_ALL=C awk '
      BEGIN { found=0 }
      /dB[[:space:]]+gain/ {
        if (match($0, /[-+]?[0-9]+(\.[0-9]+)?/)) {
          print substr($0, RSTART, RLENGTH); found=1; exit
        }
      }
      END { if (!found) exit 1 }
    ' <<< "${tsv}" 2>/dev/null)" || true
  fi

  # Normalize + validate numeric
  val="$(tr -d '[:space:]' <<< "${val}")"
  if [[ -n "${val}" && "${val}" =~ ^[-+]?[0-9]+(\.[0-9]+)?$ ]]; then
    printf -v "${__outvar}" "%s" "${val}"
    return 0
  fi
  return 1
}

# --- Scan & analyze ------------------------------------------------------------
files_ok=0
files_skipped=0

# NUL-safe iteration for any path chars
while IFS= read -r -d '' file; do
  # Per-file logs go ONLY to the gain_check.log file:
  log_file_only INFO "Checking: ${file}"

  set +e
  out="$(mp3gain -s s -o -q -- "${file}" 2>/dev/null)"
  status=$?
  set -e

  if [[ ${status} -ne 0 ]]; then
    log_file_only ERROR "mp3gain failed (${status}): ${file}"
    ((files_skipped++)) || true
    continue
  fi
  if [[ -z "${out}" ]]; then
    log_file_only WARN "Empty mp3gain output: ${file}"
    ((files_skipped++)) || true
    continue
  fi

  db=""
  if ! parse_db_gain db "${out}"; then
    flat="${out//$'\n'/ }"
    log_file_only WARN "Unable to parse dB gain: ${file} | Raw: ${flat}"
    ((files_skipped++)) || true
    continue
  fi

  abs_db="$(awk -v v="${db}" 'BEGIN { if (v<0) v=-v; print v }')"
  log_file_only INFO "dB gain=${db}, abs=${abs_db}, threshold=${GAIN_THRESHOLD}"

  # Append to processed.list: ISO8601 timestamp, absolute path, dB value
  printf "%s\t%s\t%s\n" "$(date +'%Y-%m-%dT%H:%M:%S')" "${file}" "${db}" >> "${PROCESSED_LIST}"

  cmp="$(awk -v a="${abs_db}" -v t="${GAIN_THRESHOLD}" 'BEGIN{ if (a>t) print "GT"; else print "LE" }')"
  if [[ "${cmp}" == "GT" ]]; then
    log_file_only INFO "Exceeds threshold (candidate for re-encode): ${file}"
  else
    log_file_only INFO "Within threshold: ${file}"
  fi

  ((files_ok++)) || true
done < <(find "${MUSIC_DIR}" -type f -iname '*.mp3' -print0)

log INFO "Summary: ok=${files_ok}, skipped=${files_skipped}"
log INFO "--- Run finished ---"
