#!/usr/bin/env python3
# ==============================================================================
# File:        force_plex_analyze.py
# Purpose:     Per-track "Analyze" for a Plex Music library using PlexAPI.
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Env:
#   PLEX_URL           : http://<host>:32400 (required)
#   PLEX_TOKEN         : X-Plex-Token string (required)
#   PLEX_LIBRARY       : Library name (default: "Music")
#   PLEX_RATE_DELAY    : Seconds between track analyzes (default: 0.10)
#   LOG_DIR            : Log folder (default: /data/logs)
#   LOG_PROGRESS_EVERY : Progress cadence in tracks (default: 50)
#
# Logs:
#   /data/logs/plex_analyze.log   (each line starts with [HH:MM:SS])
#   /data/logs/plex_analyze.lock  (advisory lock to prevent concurrent runs)
# ==============================================================================

import os
import sys
import time
import atexit
import fcntl
import requests
from datetime import datetime
from plexapi.server import PlexServer

def ts() -> str:
    return f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"

def getenv_clean(name: str, default: str = "") -> str:
    v = os.getenv(name, default)
    if v is None:
        v = default
    return v.strip().strip('"').strip("'")

# --------------------------- Config ---------------------------
LOG_DIR = getenv_clean("LOG_DIR", "/data/logs")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "plex_analyze.log")
LOCK_PATH = "/data/plex_analyze.lock"

PLEX_URL = getenv_clean("PLEX_URL")
PLEX_TOKEN = getenv_clean("PLEX_TOKEN")
PLEX_LIBRARY = getenv_clean("PLEX_LIBRARY") or "Music"
RATE_DELAY = float(getenv_clean("PLEX_RATE_DELAY") or "0.10")
PROGRESS_EVERY = int(getenv_clean("LOG_PROGRESS_EVERY") or "50")

# --------------------------- Logging --------------------------
def log(msg: str):
    line = f"{ts()} [PLEX] {msg}"
    # stdout (caller redirects to file too)
    print(line, flush=True)
    # file
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# --------------------------- Locking --------------------------
_lock_file = None
def acquire_lock():
    global _lock_file
    _lock_file = open(LOCK_PATH, "w")
    try:
        fcntl.flock(_lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except BlockingIOError:
        log("Another instance is already running; exiting.")
        return False

def release_lock():
    try:
        if _lock_file:
            fcntl.flock(_lock_file, fcntl.LOCK_UN)
            _lock_file.close()
    except Exception:
        pass

atexit.register(release_lock)

# --------------------------- Helpers --------------------------
def wait_for_plex(base: str, token: str, max_retries: int = 30, delay: int = 5) -> bool:
    """Check Plex is online by querying /library/sections with the token."""
    url = f"{base.rstrip('/')}/library/sections"
    for attempt in range(max_retries):
        try:
            r = requests.get(url, params={"X-Plex-Token": token}, timeout=5)
            if r.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(delay)
    return False

# --------------------------- Main -----------------------------
def main() -> int:
    if not PLEX_URL or not PLEX_TOKEN:
        log(f"ERROR: Missing PLEX_URL/PLEX_TOKEN (URL={bool(PLEX_URL)}, TOKEN={bool(PLEX_TOKEN)})")
        return 1

    if not acquire_lock():
        return 0

    log(f'Connecting to Plex at {PLEX_URL.rstrip("/")} (library="{PLEX_LIBRARY}")')

    if not wait_for_plex(PLEX_URL, PLEX_TOKEN):
        log("ERROR: Plex did not come online in time.")
        return 2

    try:
        plex = PlexServer(PLEX_URL.rstrip("/"), PLEX_TOKEN)
    except Exception as e:
        log(f"ERROR: Failed to create PlexServer: {e}")
        return 3

    # Find the Music section by library title; TYPE == 'artist' for music libraries
    try:
        target_sections = [s for s in plex.library.sections() if getattr(s, "title", "") == PLEX_LIBRARY]
        if not target_sections:
            # fallback: first music-type section
            music_sections = [s for s in plex.library.sections() if getattr(s, "TYPE", "") == "artist"]
            if not music_sections:
                log(f'ERROR: Library "{PLEX_LIBRARY}" not found and no music sections detected.')
                return 4
            section = music_sections[0]
            log(f'WARN: Library "{PLEX_LIBRARY}" not found; using music section "{section.title}".')
        else:
            section = target_sections[0]
    except Exception as e:
        log(f"ERROR: Could not list sections: {e}")
        return 5

    log("Starting per-track analyze (this will be visible in Plex Activity).")

    total = ok = fail = 0

    try:
        # Iterate artists → albums → tracks
        # section.search() returns artists; section.all() would also work.
        for artist in section.search():
            for album in artist.albums():
                for track in album.tracks():
                    total += 1
                    try:
                        # Prefer loudness-only analysis if available; fallback to full analyze.
                        loud_fn = getattr(track, "analyzeLoudness", None)
                        if callable(loud_fn):
                              loud_fn()  # issues PUT /library/metadata/{rk}/analyzeLoudness
                        else:
                              track.analyze()  # fallback: sonic+metadata analysis
                        ok += 1
                    except Exception as ex:
                            fail += 1
                            log(f'WARN: Analyze failed: "{track.title}" by "{artist.title}": {ex}')

                    if ok % PROGRESS_EVERY == 0 or total % PROGRESS_EVERY == 0:
                        log(f"Progress: ok={ok}, fail={fail}, total={total}")

                    time.sleep(RATE_DELAY)

    except KeyboardInterrupt:
        log(f"Interrupted: ok={ok}, fail={fail}, total={total}")
        return 130

    log(f"Analysis complete: ok={ok}, fail={fail}, total={total}")
    return 0

    # Loudness-only path: rely on server settings (Library → Analyze audio tracks for loudness).
    log(f"Triggering library analyze for loudness on '{section.title}' (uses server settings).")
    try:
        section.analyze()  # schedules analyze jobs; with loudness enabled and sonic off, this is loudness-only
        log("Library analyze request submitted to Plex Server.")
        return 0
    except Exception as e:
        log(f"ERROR: Library analyze request failed: {e}")
        return 6

if __name__ == "__main__":
    sys.exit(main())
