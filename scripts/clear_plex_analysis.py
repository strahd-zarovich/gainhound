#!/usr/bin/env python3
"""
===============================================================================
Script: clear_plex_analysis.py
Purpose: Clears all Plex music track analysis data using Plex API
Author: Gainhound Project
Created: 2025-08-24
===============================================================================
"""

import os
import requests
from datetime import datetime

# Load config
CONFIG_PATH = '/data/config.conf'
config = {}

with open(CONFIG_PATH, 'r') as f:
    for line in f:
        if '=' in line and not line.strip().startswith('#'):
            key, value = line.strip().split('=', 1)
            config[key.strip()] = value.strip()

# Required variables
PLEX_URL = config.get("PLEX_URL", "")
PLEX_TOKEN = config.get("PLEX_TOKEN", "")

# Logging setup
LOG_DIR = "/data/logs"
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, "clear_plex_analysis.log")

def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")
    print(f"[{timestamp}] {msg}")

def clear_plex_analysis():
    if not PLEX_URL or not PLEX_TOKEN:
        log("PLEX_URL or PLEX_TOKEN not set. Aborting.")
        return

    try:
        url = f"{PLEX_URL}/library/sections?X-Plex-Token={PLEX_TOKEN}"
        log(f"Connecting to Plex at {PLEX_URL}")
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        sections = response.json()["MediaContainer"]["Directory"]

        music_sections = [s for s in sections if s.get("type") == "artist"]
        if not music_sections:
            log("No music libraries found.")
            return

        for section in music_sections:
            section_id = section.get("key")
            section_title = section.get("title", "Unknown")
            if section_id:
                log(f"Clearing track analysis data for '{section_title}' (section {section_id})")
                clear_url = f"{PLEX_URL}/library/sections/{section_id}/unmatch?X-Plex-Token={PLEX_TOKEN}"
                requests.get(clear_url, timeout=5)

        log("Clear analysis process complete.")

    except Exception as e:
        log(f"Fatal error while clearing analysis: {e}")

if __name__ == "__main__":
    clear_plex_analysis()
