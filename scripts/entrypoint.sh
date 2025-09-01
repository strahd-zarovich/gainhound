#!/usr/bin/env bash
# ==============================================================================
# File:        entrypoint.sh
# Purpose:     Container entrypoint; sets up cron & launches desired mode.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Modes (set RUN_MODE in /data/config.conf or env):
#   • initial : Run one Gainhound cycle, then start the watcher.
#   • watch   : Start the watcher only (no immediate cycle).
#   • once    : Run one Gainhound cycle, then exit (no watcher).
#   • manual  : Do NOT auto-run tasks, but keep the container alive for testing.
#
# Logging
#   • Every line starts with "[HH:MM:SS]".
#   • High-level messages go to Docker log; sub-scripts handle their own logs.
# ==============================================================================

set -Eeo pipefail

ts() { printf "[%s]" "$(date '+%Y-%m-%d %H:%M:%S')"; }

log() {
  local level="$1"; shift || true
  echo "$(ts) [ENTRYPOINT] ${level} $*"
}

# Best-effort cleanup of stale locks at boot
cleanup_locks() {
  log "Cleaning up stale lock files..."
  rm -f /data/gainhound.lock 2>/dev/null || true
}

# Ensure config exists (do not overwrite user edits)
ensure_config() {
  if [[ -f /data/config.conf ]]; then
    log "config.conf already exists in /data"
  else
    log "WARNING: /data/config.conf missing; creating with defaults"
    cat > /data/config.conf <<'CFG'
# Minimal default config; please edit as needed.
MUSIC_DIR="/music"
RUN_MODE="initial"
RUN_GAIN_CHECK="true"
RUN_INTEGRITY_CHECK="false"
RUN_REENCODE_FOR_GAIN="false"
GAINHOUND_CRON="0 3 * * *"
PLEX_CRON=""
FORCE_PLEX_ANALYZE="false"
CFG
  fi
}

# Fix permissions (best-effort)
fix_perms() {
  log "[PERMS] Running fix_permissions.sh..."
  /scripts/fix_permissions.sh >> /data/logs/fix_permissions.log 2>&1 || true
  log "[PERMS] Completed fix_permissions.sh"
}

start_cron() {
  log "[CRON] Launching cron service..."
  /scripts/setup_cron.sh || true
  if command -v service >/dev/null 2>&1; then
    service cron start >/dev/null 2>&1 || true
  else
    cron >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
# Keep-alive loop for MANUAL mode:
#   • Prevents container from exiting (and thus being restarted by Docker).
#   • Does not run Gainhound or watcher.
# ------------------------------------------------------------------------------
idle_forever() {
  log "RUN_MODE is 'manual': Not starting Gainhound or watcher."
  log "RUN_MODE is 'manual': Idling to keep the container alive..."
  # Sleep in long intervals; trap allows clean stop
  trap 'log "Stopping (manual idle)..."; exit 0' TERM INT
  while true; do
    sleep 3600
  done
}

main() {
  log "Starting Gainhound container..."
  cleanup_locks
  ensure_config
  fix_perms
  start_cron

  # shellcheck disable=SC1091
  source /data/config.conf 2>/dev/null || true
  RUN_MODE="${RUN_MODE:-initial}"

  case "${RUN_MODE}" in
    manual)
      idle_forever
      ;;
    once)
      log "RUN_MODE is 'once': Running a single Gainhound cycle..."
      /scripts/run_gainhound.sh
      ;;
    watch)
      log "RUN_MODE is 'watch': Starting watch mode only..."
      /scripts/watch_music.sh
      ;;
    initial|*)
      log "RUN_MODE is 'initial': Running initial scan and starting watch mode..."
      /scripts/run_gainhound.sh || true
      /scripts/watch_music.sh
      ;;
  esac
}

main "$@"
