#!/bin/bash
# ============================================================================
# Script: fix_permissions.sh
# Purpose: Ensures proper file permissions for /data and logs
# Author: Gainhound Project
# Notes:
#   - Should be run at container start and via cron to fix any issues.
# ============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PERMS] Fixing permissions..."

chown -R 99:100 /data
chmod -R g+rw /data
find /data -type d -exec chmod g+s {} \;

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PERMS] Permissions fixed."
