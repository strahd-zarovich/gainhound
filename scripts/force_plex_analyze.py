#!/usr/bin/env python3
# ==============================================================================
# File:        force_plex_analyze.py
# Purpose:     Library-level Scan -> optional Analyze for a Plex Music library.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Env (config.conf):
#   FORCE_PLEX_ANALYZE   : true|false  (if false, script logs+exits 0)
#   PLEX_ANALYZE_LOUDNESS: true|false  (if true, run section.analyze() after scan)
#   PLEX_URL             : http://<host>:32400  (required when FORCE_PLEX_ANALYZE=true)
#   PLEX_TOKEN           : X-Plex-Token string  (required when FORCE_PLEX_ANALYZE=true)
#   PLEX_LIBRARY         : Library title (default: "Music")
#   LOG_DIR              : Log folder (default: /data/logs)
#
# Logs:
#   /data/logs/plex_analyze.log   (each line starts with [YYYY-MM-DD HH:MM:SS])
#   /data/plex_analyze.lock       (advisory lock to prevent concurrent runs)
# ==============================================================================

import os
import sys
import time
import atexit
import fcntl
import requests
from datetime import datetime
from plexapi.server import PlexServer

# ------------- utils / logging -------------
def ts() -> str:
    return f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"

def getenv_clean(name: str, default: str | None = None) -> str | None:
    v = os.getenv(name, default)
    if v is None:
        return None
    v = v.strip()
    if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
        v = v[1:-1]
    return v

LOG_DIR = getenv_clean("LOG_DIR") or "/data/logs"
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "plex_analyze.log")

def log(msg: str) -> None:
    line = f"{ts()} [PLEX] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# ------------- config -------------
FORCE_PLEX_ANALYZE    = (getenv_clean("FORCE_PLEX_ANALYZE") or "false").lower() in ("1","true","yes","on","y")
PLEX_ANALYZE_LOUDNESS = (getenv_clean("PLEX_ANALYZE_LOUDNESS") or "false").lower() in ("1","true","yes","on","y")

PLEX_URL      = getenv_clean("PLEX_URL")
PLEX_TOKEN    = getenv_clean("PLEX_TOKEN")
PLEX_LIBRARY  = getenv_clean("PLEX_LIBRARY") or "Music"

LOCK_PATH = "/data/plex_analyze.lock"
_lock_fh = None

def acquire_lock() -> bool:
    global _lock_fh
    try:
        _lock_fh = open(LOCK_PATH, "a+")
        fcntl.flock(_lock_fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        _lock_fh.seek(0); _lock_fh.truncate()
        _lock_fh.write(f"{os.getpid()}\n"); _lock_fh.flush()
        return True
    except BlockingIOError:
        log("Another instance is already running; exiting.")
        return False
    except Exception as e:
        log(f"ERROR: Could not open/lock {LOCK_PATH}: {e}")
        return False

def release_lock():
    try:
        if _lock_fh:
            fcntl.flock(_lock_fh, fcntl.LOCK_UN)
            _lock_fh.close()
    except Exception:
        pass

atexit.register(release_lock)

def wait_for_plex(base: str, token: str, tries: int = 30, delay: float = 2.0) -> bool:
    """Light readiness probe against /library/sections with token."""
    url = f"{base.rstrip('/')}/library/sections"
    for _ in range(tries):
        try:
            r = requests.get(url, params={"X-Plex-Token": token}, timeout=5)
            if r.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(delay)
    return False

def main() -> int:
    # Disabled? Exit cleanly so cron logs stay quiet.
    if not FORCE_PLEX_ANALYZE:
        log("FORCE_PLEX_ANALYZE=false; nothing to do.")
        return 0

    # Require URL/token only when enabled
    if not PLEX_URL or not PLEX_TOKEN:
        log(f"ERROR: Missing PLEX_URL/PLEX_TOKEN (URL={bool(PLEX_URL)}, TOKEN={bool(PLEX_TOKEN)})")
        return 2

    if not acquire_lock():
        return 0

    log(f'Connecting to Plex at {PLEX_URL.rstrip("/")} (library="{PLEX_LIBRARY}")')

    if not wait_for_plex(PLEX_URL, PLEX_TOKEN):
        log("ERROR: Plex did not come online in time.")
        return 3

    # Connect
    try:
        plex = PlexServer(PLEX_URL.rstrip("/"), PLEX_TOKEN)
    except Exception as e:
        log(f"ERROR: Failed to create PlexServer: {e}")
        return 4

    # Locate section
    try:
        section = next(s for s in plex.library.sections() if getattr(s, "title", "") == PLEX_LIBRARY)
    except StopIteration:
        # fallback: first music-type section
        try:
            section = next(s for s in plex.library.sections() if getattr(s, "TYPE", "") == "artist")
            log(f'WARN: Library "{PLEX_LIBRARY}" not found; using music section "{section.title}".')
        except StopIteration:
            log(f'ERROR: Library "{PLEX_LIBRARY}" not found and no music sections detected.')
            return 5
    except Exception as e:
        log(f"ERROR: Could not list sections: {e}")
        return 6

    # --- SCAN (always when FORCE_PLEX_ANALYZE=true) ---
    try:
        log(f'Starting library scan (update) on "{section.title}"...')
        section.update()  # "Scan Library Files"
        log("Library scan submitted to Plex Server.")
    except Exception as e:
        log(f"ERROR: Library scan request failed: {e}")
        return 7

    # --- ANALYZE (only if PLEX_ANALYZE_LOUDNESS=true) ---
    if PLEX_ANALYZE_LOUDNESS:
        try:
            log(f'Starting library analyze on "{section.title}" (server settings decide loudness/sonic)...')
            section.analyze()  # schedules analyze jobs; respects server toggles
            log("Library analyze request submitted to Plex Server.")
        except Exception as e:
            log(f"ERROR: Library analyze request failed: {e}")
            return 8
    else:
        log("PLEX_ANALYZE_LOUDNESS=false; skipping library analyze.")

    log("Plex Scan/Analyze cycle finished.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
