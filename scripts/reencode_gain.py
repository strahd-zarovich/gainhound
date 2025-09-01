#!/usr/bin/env python3
# ==============================================================================
# File:        reencode_gain.py
# Purpose:     Re-encode over-threshold MP3s, drop mp3gain tags, update processed list
# Author:      Gainhound Project
# ------------------------------------------------------------------------------
# Behavior:
#   • Reads candidates from /data/processed.list (format: "<timestamp>\t<path>\t<gain>")
#   • Selects tracks where abs(gain) >= GAIN_THRESHOLD
#   • Re-encodes each candidate in-place using ffmpeg (basic tags preserved)
#   • Removes mp3gain/APE tags on the output (mp3gain -s d)
#   • Atomically replaces the source file with the new file
#   • Removes the file’s line from /data/processed.list (so mp3gain runs again later)
#   • Logs to /data/logs/reencode_gain.log with [HH:MM:SS] prefix
#   • On exit, triggers /scripts/plex_analyze.sh (best-effort; exit code preserved)
#
# Env:
#   MUSIC_DIR           (default: /music)
#   GAIN_THRESHOLD      (default: 5)
#   LOG_DIR             (default: /data/logs)
#   FFMPEG_VBR_QUALITY  (optional; default: 2 for libmp3lame VBR ~190kbps)
#   ID3_VERSION         (optional; 3 -> ID3v2.3 write; default: 3)
#   MAX_FILES           (optional; process at most N files, then stop)
#   DRY_RUN             (optional; "1" = list candidates but do not modify files)
# ==============================================================================

import os
import sys
import shlex
import time
import atexit
import tempfile
import subprocess
import errno 
import shutil
from datetime import datetime

# --------------------------- Config / Constants -------------------------------

def ts() -> str:
    """Return [HH:MM:SS] timestamp string for log lines."""
    return f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]"

def getenv_clean(name: str, default: str = "") -> str:
    v = os.getenv(name, default)
    if v is None:
        v = default
    return v.strip().strip('"').strip("'")

LOG_DIR     = getenv_clean("LOG_DIR", "/data/logs")
LOG_PATH    = os.path.join(LOG_DIR, "reencode_gain.log")
PROC_LIST   = "/data/processed.list"

MUSIC_DIR   = getenv_clean("MUSIC_DIR", "/music")
THRESH_STR  = getenv_clean("GAIN_THRESHOLD", "5")
FF_VBR_Q    = getenv_clean("FFMPEG_VBR_QUALITY", "2")
ID3_VER     = getenv_clean("ID3_VERSION", "3")
MAX_FILES   = getenv_clean("MAX_FILES", "")
DRY_RUN     = getenv_clean("DRY_RUN", "")

try:
    GAIN_THRESHOLD = float(THRESH_STR)
except ValueError:
    GAIN_THRESHOLD = 5.0

try:
    MAX_FILES_INT = int(MAX_FILES) if MAX_FILES else None
except ValueError:
    MAX_FILES_INT = None

# --------------------------- Logging ------------------------------------------

def log(msg: str):
    line = f"{ts()} [REENCODE] {msg}"
    # stdout (for docker log readability)
    print(line, flush=True)
    # file log
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# --------------------------- Helpers ------------------------------------------

def run(cmd: list[str]) -> subprocess.CompletedProcess:
    """Run a command and return the CompletedProcess."""
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

def safe_replace(src_tmp: str, dst_final: str) -> None:
    """
    Atomic replace when on same filesystem. If EXDEV (cross-device) occurs,
    fall back to copy+rename within the destination directory.
    """
    try:
        os.replace(src_tmp, dst_final)
    except OSError as ex:
        if ex.errno == errno.EXDEV:
            dst_dir = os.path.dirname(dst_final) or "."
            alt_tmp = os.path.join(dst_dir, f".swap.{os.path.basename(dst_final)}.tmp")
            shutil.copy2(src_tmp, alt_tmp)
            os.replace(alt_tmp, dst_final)
            os.remove(src_tmp)
        else:
            raise

def strip_mp3gain_tags(path: str) -> None:
    """
    Remove mp3gain APEv2 tags if present. This does NOT touch normal ID3 frames.
    mp3gain: -s d  -> delete APEv2 tags
    """
    run(["mp3gain", "-s", "d", path])

def remove_from_processed_list(song_path: str) -> None:
    """
    Delete any entry from /data/processed.list whose 2nd field equals song_path.
    """
    try:
        if not os.path.exists(PROC_LIST):
            return

        with open(PROC_LIST, "r", encoding="utf-8", errors="ignore") as fin:
            lines = fin.readlines()

        proc_dir = os.path.dirname(PROC_LIST) or "."
        # temp file created in the same dir to avoid cross-device errors
        with tempfile.NamedTemporaryFile("w", delete=False, dir=proc_dir, encoding="utf-8") as out:
            for line in lines:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 3:
                    out.write(line)
                    continue
                _ts, pth, _gain = parts
                if pth == song_path:
                    # skip this line entirely (delete it)
                    continue
                out.write(line)

        # atomic swap within same FS
        os.replace(out.name, PROC_LIST)

    except Exception as ex:
        log(f"[WARN] Could not update processed.list for '{song_path}': {ex}")

def ffmpeg_reencode(src: str, dst_tmp: str) -> tuple[bool, str]:
    """
    Re-encode MP3 using libmp3lame with VBR quality (default q=2),
    write ID3v2.3 tags, preserve basic tags/cover art via -map 0 and -map_metadata 0.
    Returns (ok, excerpt_of_output).
    """
    # Build ffmpeg command
    # -y: overwrite temp file
    # -map 0: keep all streams (audio + cover art), but we'll enforce mp3 output container
    # -map_metadata 0: copy source metadata (basic tags)
    # -codec:a libmp3lame -q:a <VBR>: re-encode audio
    # -id3v2_version 3: standard ID3v2.3
    cmd = [
        "ffmpeg", "-y",
        "-i", src,
        "-map", "0",
        "-map_metadata", "0",
        "-codec:a", "libmp3lame",
        "-q:a", FF_VBR_Q,
        "-id3v2_version", ID3_VER,
        dst_tmp,
    ]
    res = run(cmd)
    ok = (res.returncode == 0)
    snippet = (res.stdout or "")[:240].replace("\n", " ")
    return ok, snippet

def list_candidates_from_processed(threshold: float) -> list[tuple[str, float]]:
    """
    Parse /data/processed.list and return [(path, gain_float), ...] where abs(gain) >= threshold.
    """
    cands: list[tuple[str, float]] = []
    if not os.path.exists(PROC_LIST):
        log(f"[WARN] No {PROC_LIST} found; nothing to do.")
        return cands
    with open(PROC_LIST, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            _ts, path, gain_str = parts
            try:
                gain = float(gain_str)
            except ValueError:
                continue
            if abs(gain) >= threshold and path.lower().endswith(".mp3"):
                cands.append((path, gain))
    return cands

# --------------------------- Plex Analyze (post hook) -------------------------

def analyze_plex_posthook():
    """
    Trigger /scripts/plex_analyze.sh after re-encode completes.

    Modes (env):
      POSTHOOK_MODE:
        - "bg"  (default): fire-and-forget in background (non-blocking)
        - "sync": run synchronously
      POSTHOOK_TIMEOUT:
        - only used when POSTHOOK_MODE="sync"
        - integer seconds (default: 60)

    This should not alter the Python exit code.
    """
    script = "/scripts/plex_analyze.sh"
    mode   = getenv_clean("POSTHOOK_MODE", "bg").lower()
    try:
        timeout = int(getenv_clean("POSTHOOK_TIMEOUT", "60"))
    except ValueError:
        timeout = 60

    if not os.path.exists(script):
        log("[INFO] Plex analyze script not found; skipping post-hook.")
        return

    if mode == "bg":
        # Non-blocking: detach and return immediately
        log("[INFO] Triggering Plex analyze post-hook (mode=bg)...")
        try:
            # Send stdout/stderr to /dev/null so this never blocks exit
            with open(os.devnull, "wb") as devnull:
                subprocess.Popen([script], stdout=devnull, stderr=subprocess.STDOUT)
            log("[INFO] Plex analyze launched in background.")
        except Exception as ex:
            log(f"[WARN] Failed to launch Plex analyze in background: {ex}")
        return

    # Synchronous with timeout
    log(f"[INFO] Triggering Plex analyze post-hook (mode=sync, timeout={timeout}s)...")
    try:
        res = subprocess.run([script], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, timeout=timeout)
        code = res.returncode
        tail = (res.stdout or "")[-240:].replace("\n", " ")
        if code == 0:
            log("[INFO] Plex analyze completed (rc=0).")
        else:
            log(f"[WARN] Plex analyze exited with rc={code}; tail: {tail}")
    except subprocess.TimeoutExpired:
        log(f"[WARN] Plex analyze timed out after {timeout}s (continuing).")
    except Exception as ex:
        log(f"[WARN] Failed to invoke Plex analyze: {ex}")

@atexit.register
def _post_exit():
    # Ensure Plex analyze runs even if we exit early (best effort).
    analyze_plex_posthook()

# --------------------------- Main --------------------------------------------

def main() -> int:
    # Banner
    log(f"Starting re-encode scan (threshold={GAIN_THRESHOLD} dB, dir={MUSIC_DIR})")
    if DRY_RUN == "1":
        log("[INFO] DRY_RUN=1 — will list candidates only, no writes.")

    all_candidates = list_candidates_from_processed(GAIN_THRESHOLD)
    grand_total = len(all_candidates)

    candidates = all_candidates
    if MAX_FILES_INT is not None:
        candidates = all_candidates[:MAX_FILES_INT]
    batch_total = len(candidates)

    log(f"[INFO] Candidates available: {grand_total} | This batch: {batch_total}")


    # Initialize counters for the loop
    total = batch_total
    ok = 0
    fail = 0
    done = 0

    if batch_total == 0:
        log("[INFO] No candidates to process.")
        return 0

    for (path, gain) in candidates:
        done += 1
        if DRY_RUN == "1":
            log(f"[DRY] {path} (gain={gain:+.2f} dB)")
            continue

        # Ensure path lives under MUSIC_DIR (safety)
        try:
            norm_music = os.path.realpath(MUSIC_DIR)
            norm_path  = os.path.realpath(path)
            if not norm_path.startswith(norm_music + os.sep) and norm_path != norm_music:
                log(f"[WARN] Skipping outside MUSIC_DIR: {path}")
                continue
        except Exception:
            pass

        # Prepare a temp output in the same directory for atomic swap
        out_tmp = f"{path}.reenc.tmp.mp3"

        ok_ff, out_snip = ffmpeg_reencode(path, out_tmp)
        if not ok_ff:
            fail += 1
            log(f"[ERROR] ffmpeg failed: {path} (gain={gain:+.2f} dB) :: {out_snip}")
            # Clean temp on failure
            try:
                if os.path.exists(out_tmp):
                    os.remove(out_tmp)
            except Exception:
                pass
            continue

        # Remove mp3gain APE tags from the new file
        strip_mp3gain_tags(out_tmp)

        # Replace original atomically
        try:
            safe_replace(out_tmp, path)
        except Exception as ex:
            fail += 1
            log(f"[ERROR] Atomic replace failed for: {path} :: {ex}")
            # Attempt to clean temp
            try:
                if os.path.exists(out_tmp):
                    os.remove(out_tmp)
            except Exception:
                pass
            continue

        # Update bookkeeping: remove from processed.list so mp3gain will re-analyze later
        remove_from_processed_list(path)

        ok += 1
        if ok % 25 == 0 or done % 25 == 0:
            log(f"[INFO] Progress: ok={ok}, fail={fail}, done={done}/{total}")

        log(f"[INFO] Re-encoded: {path} (gain was {gain:+.2f} dB)")

    # Summary
    if DRY_RUN == "1":
        log(f"DRY RUN complete: listed={batch_total}")
        return 0

    log(f"Re-encode complete: ok={ok}, fail={fail}, total={batch_total}")

    # Recompute remaining candidates after deletions from processed.list
    try:
        remaining = len(list_candidates_from_processed(GAIN_THRESHOLD))
        log(f"[INFO] Remaining candidates: {remaining}")
    except Exception as ex:
        log(f"[WARN] Could not compute remaining candidates: {ex}")

    return 0 if fail == 0 else 3

if __name__ == "__main__":
    sys.exit(main())
