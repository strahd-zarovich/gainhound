# -----------------------------------------------------
# Gainhound Dockerfile
# Lightweight container for MP3 gain analysis, integrity checks, and re-encoding
# Based on Python 3.11 slim
# -----------------------------------------------------

FROM python:3.11-slim

ARG VERSION=0.0.0
LABEL version="${VERSION}"

# ---------------------------
# Install required packages
# ---------------------------
RUN apt-get update && apt-get install -y \
    mp3gain \
    ffmpeg \
    cron \
    bash \
    inotify-tools \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------
# Install required python packages
# ---------------------------
RUN pip3 install --no-cache-dir plexapi requests

# ---------------------------
# Copy scripts and config
# ---------------------------
COPY ./scripts /scripts
COPY ./config /defaults

# ---------------------------
# Set permissions
# ---------------------------
RUN chmod +x /scripts/*.sh && \
    chmod +x /scripts/*.py && \
    mkdir -p /data /data/logs && \
    touch /data/processed.list && \
    chmod 664 /data/processed.list

# ---------------------------
# Set working directory
# ---------------------------
WORKDIR /scripts

# ---------------------------
# Start script
# ---------------------------
ENTRYPOINT ["/scripts/entrypoint.sh"]
