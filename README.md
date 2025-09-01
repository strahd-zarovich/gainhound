# Gainhound

Gainhound is a focused MP3 normalization container that checks and adjusts audio gain, file integrity, and optionally re-encodes MP3 files when significant gain changes are detected.

## Features

- Gain analysis using `mp3gain`
- Integrity checks using `ffmpeg`
- Optional re-encode via `ffmpeg` when gain shifts are too large
- Optional forced Plex audio analysis via PlexAPI
- Clean log and state management with daily cleanup

## Configuration

All settings are controlled via `config.conf`:

```conf
# Folder with MP3 files to normalize
MUSIC_DIR="/music"

# General execution mode: 'initial' or 'undo'
RUN_MODE="initial"

# Scheduled cron job for main functions (gain/integrity/encode)
CRON_SCHEDULE="0 3 * * *" # daily at 5AM

# Execution Toggles
RUN_GAIN_CHECK=false
RUN_INTEGRITY_CHECK=false
RUN_REENCODE_FOR_GAIN=false

# Cron Schedule for Plex Force Analyze (only used if FORCE_PLEX_ANALYZE=true)
PLEX_CRON="0 0 * * WED"  # daily at 5AM

# Plex
PLEX_URL=http://localhost:32400
PLEX_TOKEN=your_token_here
```

## Folder Structure

```
/scripts/
  gain_check.sh
  integrity_check.sh
  reencode_high_gain.sh
  cleanup_logs.sh
  undo_gain_changes.sh
  plex_force_analyze.py
entrypoint.sh
config.conf
```

## Logs

Logs are rotated daily and stored in `/data/logs`. A file `/data/processed.list` (non-hidden) is used to track completed files and avoid reprocessing.

# gainhound
