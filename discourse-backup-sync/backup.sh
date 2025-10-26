#!/bin/bash
set -e

# Load configuration from web UI config file
CONFIG_FILE="/data/config.json"
SSH_KEY_PATH="/data/ssh_key"

# Function to reload config
reload_config() {
    if [ -f "$CONFIG_FILE" ]; then
        REMOTE_HOST=$(jq -r '.remote_host // ""' "$CONFIG_FILE")
        REMOTE_USER=$(jq -r '.remote_user // ""' "$CONFIG_FILE")
        REMOTE_PORT=$(jq -r '.remote_port // 22' "$CONFIG_FILE")
        REMOTE_BACKUP_PATH=$(jq -r '.remote_backup_path // ""' "$CONFIG_FILE")
        LOCAL_BACKUP_BASE=$(jq -r '.backup_storage_path // "/backup/discourse"' "$CONFIG_FILE")
        DAILY_RETENTION=$(jq -r '.daily_retention_days // 7' "$CONFIG_FILE")
        WEEKLY_RETENTION=$(jq -r '.weekly_retention_days // 90' "$CONFIG_FILE")
        MONTHLY_RETENTION=$(jq -r '.monthly_retention_days // 730' "$CONFIG_FILE")
    else
        LOCAL_BACKUP_BASE="/backup/discourse"
        DAILY_RETENTION=7
        WEEKLY_RETENTION=90
        MONTHLY_RETENTION=730
    fi
}

# Load config
reload_config

LOCAL_DAILY="$LOCAL_BACKUP_BASE/daily"
LOCAL_WEEKLY="$LOCAL_BACKUP_BASE/weekly"
LOCAL_MONTHLY="$LOCAL_BACKUP_BASE/monthly"
LOG_FILE="$LOCAL_BACKUP_BASE/backup.log"

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Check if SSH is configured
if [ ! -f "$SSH_KEY_PATH" ]; then
    log ERROR "SSH key not found. Please configure SSH via the web UI."
    exit 1
fi

# Check if we have required config
if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_USER" ]; then
    log WARNING "Remote host or user not configured. Please configure via web UI."
    exit 1
fi

log INFO "=== Starting backup sync ==="

# Find the most recent backup on remote server
LATEST_BACKUP=$(ssh -p "$REMOTE_PORT" -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "ls -t $REMOTE_BACKUP_PATH/*.tar.gz 2>/dev/null | head -1")

if [ -z "$LATEST_BACKUP" ]; then
    log ERROR "No backups found on remote server at $REMOTE_BACKUP_PATH"
    exit 1
fi

BACKUP_FILENAME=$(basename "$LATEST_BACKUP")
log INFO "Found latest backup: $BACKUP_FILENAME"

# Check if we already have this backup
if [ -f "$LOCAL_DAILY/$BACKUP_FILENAME" ]; then
    log INFO "Backup already exists locally, skipping download"
else
    # Download the latest backup
    log INFO "Downloading backup..."
    if scp -P "$REMOTE_PORT" -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:$LATEST_BACKUP" "$LOCAL_DAILY/"; then
        log INFO "Successfully downloaded: $BACKUP_FILENAME"
    else
        log ERROR "Failed to download backup"
        exit 1
    fi
fi

# Get current date info
DAY_OF_WEEK=$(date +%u)  # 1-7 (Monday-Sunday)
DAY_OF_MONTH=$(date +%d)

# Weekly backup (every Sunday - day 7)
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    log INFO "Creating weekly backup..."
    cp "$LOCAL_DAILY/$BACKUP_FILENAME" "$LOCAL_WEEKLY/"
fi

# Monthly backup (first day of month)
if [ "$DAY_OF_MONTH" = "01" ]; then
    log INFO "Creating monthly backup..."
    cp "$LOCAL_DAILY/$BACKUP_FILENAME" "$LOCAL_MONTHLY/"
fi

# Cleanup old backups
log INFO "Cleaning up old backups..."

# Remove daily backups older than retention period
DAILY_DELETED=$(find "$LOCAL_DAILY" -name "*.tar.gz" -type f -mtime +$DAILY_RETENTION -delete -print | wc -l)
log INFO "Removed $DAILY_DELETED old daily backups"

# Remove weekly backups older than retention period
WEEKLY_DELETED=$(find "$LOCAL_WEEKLY" -name "*.tar.gz" -type f -mtime +$WEEKLY_RETENTION -delete -print | wc -l)