* **Overview:** What Gainhound does (gain scan → integrity → optional re-encode → trigger Plex loudness analyze).
* **Directories / mounts:**

  * `/music` → your library (bind from host)
  * `/data` → state/logs/config (`config.conf`, `processed.list`, logs)
* **Config (`/data/config.conf`):**

  * `RUN_MODE` (`initial|watch|once|manual`)
  * `RUN_GAIN_CHECK`, `RUN_INTEGRITY_CHECK`, `RUN_REENCODE_FOR_GAIN`
  * `GAIN_THRESHOLD` (dB; absolute, handles + and −)
  * `GAINHOUND_CRON` (e.g., `0 3 * * *`)
  * Plex: `FORCE_PLEX_ANALYZE`, `PLEX_URL`, `PLEX_TOKEN`
* **Cron & rotation:**

  * `setup_cron.sh` writes `/etc/cron.d/gainhound_jobs`
  * Nightly rotation via `log_rotate.sh` (date-stamped `.gz`), and logs themselves now include `[YYYY-MM-DD HH:MM:SS]`.
* **Re-encode flow:**

  * `reencode.sh` (shell wrapper) → `reencode_gain.py` (selection + ffmpeg)
  * After a successful re-encode: remove from `processed.list`, then post-hook triggers `plex_analyze.sh`
* **Plex loudness analyze (not sonic):**

  * We trigger **library-level** analyze via `force_plex_analyze.py` called from `plex_analyze.sh`.
  * Ensure server setting **“Analyze audio tracks for loudness”** is enabled; disable sonic if you don’t want the heavy pass.
* **Manual test commands:**

  * `bash /scripts/gain_check.sh`
  * `bash /scripts/integrity_check.sh`
  * `bash /scripts/reencode.sh` (supports `MAX_FILES`)
  * `bash /scripts/plex_analyze.sh`
* **Docker/Compose examples:** include corrected compose above and a `docker run` sample.
* **Optional utilities:** `undo_gain.sh` (describe usage if you intend to keep it).

# Small consistency tweaks (nice to have)

* **Logging:** you already added full `[YYYY-MM-DD HH:MM:SS]` across scripts—good. Consider bumping `normalize_mp3s.sh` timestamps if you keep it (currently HH\:MM\:SS only).
* **Single source of truth for log retention:** if you want `cleanup_logs.sh` age-based deletion, add it to `setup_cron.sh` (e.g., `0 4 * * * root /scripts/cleanup_logs.sh >> /data/logs/cron_logcleanup.log 2>&1`). Otherwise delete it.
* **README badges / sections:** add “Known limitations” (e.g., extremely abnormal “silence” files can appear as > +20 dB; we can filter them if you want).
