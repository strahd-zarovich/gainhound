# TODO (Future Enhancements)

* [ ] **Skip silence/junk files**
  Add filter to ignore abnormal candidates (e.g. `abs(gain) > 20 dB` or filenames containing “silence”).

* [ ] **Daily summary report**
  Generate one consolidated log/report with counts of:

  * Gain check files scanned
  * Integrity check passes/fails
  * Re-encodes performed
  * Plex analyze runs triggered

* [ ] **Optional log cleanup**
  Decide whether to wire `cleanup_logs.sh` into cron for age-based deletion (e.g. purge logs >14 days old).

* [ ] **Plex analyzer preflight check**
  Script should warn if “Analyze audio tracks for loudness” is disabled, to prevent accidental heavy sonic scans.

* [ ] **Enhance processed.list**
  Add timestamp or reason (gain / integrity / re-encode) for each entry for better traceability.

* [ ] **Metadata preservation (optional)**
  Review re-encode step if you want to retain richer tags (album art, lyrics, comments).