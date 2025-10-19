#!/usr/bin/with-contenv bashio

# Load configuration from web UI config file
CONFIG_FILE="/data/config.json"

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
        SCHEDULE=$(jq -r '.schedule // "0 3 * * *"' "$CONFIG_FILE")
    else
        # Use defaults if config doesn't exist yet
        REMOTE_HOST=""
        REMOTE_USER=""
        REMOTE_PORT=22
        REMOTE_BACKUP_PATH=""
        LOCAL_BACKUP_BASE="/backup/discourse"
        DAILY_RETENTION=7
        WEEKLY_RETENTION=90
        MONTHLY_RETENTION=730
        SCHEDULE="0 3 * * *"
    fi
}

# Get add-on options (only log level now)
LOG_LEVEL=$(bashio::config 'log_level')

# Create directories
mkdir -p /data

# Load initial config
reload_config

SSH_KEY_PATH="/data/ssh_key"

# Check if SSH is configured by looking for the key file
SSH_CONFIGURED=false
if [ -f "$SSH_KEY_PATH" ]; then
    SSH_CONFIGURED=true
fi

LOCAL_DAILY="$LOCAL_BACKUP_BASE/daily"
LOCAL_WEEKLY="$LOCAL_BACKUP_BASE/weekly"
LOCAL_MONTHLY="$LOCAL_BACKUP_BASE/monthly"
LOG_FILE="$LOCAL_BACKUP_BASE/backup.log"

# Create directories
mkdir -p "$LOCAL_DAILY" "$LOCAL_WEEKLY" "$LOCAL_MONTHLY"
mkdir -p /data

# Set up SSH if configured
if [ "$SSH_CONFIGURED" = "true" ] && [ -f "$SSH_KEY_PATH" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cp "$SSH_KEY_PATH" ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan -p "$REMOTE_PORT" -H "$REMOTE_HOST" >> ~/.ssh/known_hosts 2>/dev/null
fi

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"

    case $level in
        ERROR)
            bashio::log.error "$message"
            ;;
        WARNING)
            bashio::log.warning "$message"
            ;;
        INFO)
            bashio::log.info "$message"
            ;;
        DEBUG)
            bashio::log.debug "$message"
            ;;
    esac
}

# Backup sync function
sync_backup() {
    # Reload config in case it changed
    reload_config

    if [ "$SSH_CONFIGURED" != "true" ]; then
        log WARNING "SSH not configured. Please configure SSH via the web UI."
        return 1
    fi

    if [ ! -f "$SSH_KEY_PATH" ]; then
        log ERROR "SSH key not found. Please reconfigure SSH via the web UI."
        return 1
    fi

    # Check if we have required config
    if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_USER" ]; then
        log WARNING "Remote host or user not configured. Please configure via web UI."
        return 1
    fi

    log INFO "=== Starting backup sync ==="

    # Find the most recent backup on remote server
    LATEST_BACKUP=$(ssh -p "$REMOTE_PORT" -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "ls -t $REMOTE_BACKUP_PATH/*.tar.gz 2>/dev/null | head -1")

    if [ -z "$LATEST_BACKUP" ]; then
        log ERROR "No backups found on remote server at $REMOTE_BACKUP_PATH"
        return 1
    fi

    BACKUP_FILENAME=$(basename "$LATEST_BACKUP")
    log INFO "Found latest backup: $BACKUP_FILENAME"

    # Check if we already have this backup
    if [ -f "$LOCAL_DAILY/$BACKUP_FILENAME" ]; then
        log INFO "Backup already exists locally, skipping download"
    else
        # Download the latest backup
        log INFO "Downloading backup..."
        if scp -P "$REMOTE_PORT" -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:$LATEST_BACKUP" "$LOCAL_DAILY/"; then
            log INFO "Successfully downloaded: $BACKUP_FILENAME"
        else
            log ERROR "Failed to download backup"
            return 1
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
    log INFO "Removed $WEEKLY_DELETED old weekly backups"

    # Remove monthly backups older than retention period
    MONTHLY_DELETED=$(find "$LOCAL_MONTHLY" -name "*.tar.gz" -type f -mtime +$MONTHLY_RETENTION -delete -print | wc -l)
    log INFO "Removed $MONTHLY_DELETED old monthly backups"

    # Report backup counts
    DAILY_COUNT=$(find "$LOCAL_DAILY" -name "*.tar.gz" -type f | wc -l)
    WEEKLY_COUNT=$(find "$LOCAL_WEEKLY" -name "*.tar.gz" -type f | wc -l)
    MONTHLY_COUNT=$(find "$LOCAL_MONTHLY" -name "*.tar.gz" -type f | wc -l)

    log INFO "Current backup counts - Daily: $DAILY_COUNT, Weekly: $WEEKLY_COUNT, Monthly: $MONTHLY_COUNT"
    log INFO "=== Backup sync completed successfully ==="
}

# Start web UI in background
bashio::log.info "Starting web UI on port 8099..."
cd /app
python3 web_ui.py &
WEB_UI_PID=$!

# Wait for web UI to start
sleep 3

bashio::log.info "Discourse Backup Sync started"
bashio::log.info "Web UI available - click 'Open Web UI' to configure"

if [ "$SSH_CONFIGURED" = "true" ] && [ -n "$REMOTE_HOST" ]; then
    # Set up cron job
    echo "$SCHEDULE /run_backup.sh" > /etc/crontabs/root

    # Create wrapper script for cron
    cat > /run_backup.sh << 'EOF'
#!/bin/bash
source /run.sh
sync_backup
EOF
    chmod +x /run_backup.sh

    bashio::log.info "SSH configured - backups will sync automatically"
    bashio::log.info "Schedule: $SCHEDULE"
    bashio::log.info "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_PATH"
    bashio::log.info "Local storage: $LOCAL_BACKUP_BASE"
    bashio::log.info "Retention - Daily: ${DAILY_RETENTION}d, Weekly: ${WEEKLY_RETENTION}d, Monthly: ${MONTHLY_RETENTION}d"

    # Run initial sync
    sync_backup

    # Start cron in background
    bashio::log.info "Starting cron daemon..."
    crond -l 2
fi

# Keep container running (wait for web UI process)
bashio::log.info "Add-on is running. Access the web UI to manage backups."
wait $WEB_UI_PID
LOCAL_WEEKLY="$LOCAL_BACKUP_BASE/weekly"
LOCAL_MONTHLY="$LOCAL_BACKUP_BASE/monthly"
LOG_FILE="$LOCAL_BACKUP_BASE/backup.log"

# Create directories
mkdir -p "$LOCAL_DAILY" "$LOCAL_WEEKLY" "$LOCAL_MONTHLY"
mkdir -p /data

# Set up SSH if configured
if [ "$SSH_CONFIGURED" = "true" ] && [ -f "$SSH_KEY_PATH" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cp "$SSH_KEY_PATH" ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan -p "$REMOTE_PORT" -H "$REMOTE_HOST" >> ~/.ssh/known_hosts 2>/dev/null
fi

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"

    case $level in
        ERROR)
            bashio::log.error "$message"
            ;;
        WARNING)
            bashio::log.warning "$message"
            ;;
        INFO)
            bashio::log.info "$message"
            ;;
        DEBUG)
            bashio::log.debug "$message"
            ;;
    esac
}

# Backup sync function
sync_backup() {
    if [ "$SSH_CONFIGURED" != "true" ]; then
        log WARNING "SSH not configured. Please configure SSH via the web UI."
        return 1
    fi

    if [ ! -f "$SSH_KEY_PATH" ]; then
        log ERROR "SSH key not found. Please reconfigure SSH via the web UI."
        return 1
    fi

    log INFO "=== Starting backup sync ==="

    # Find the most recent backup on remote server
    LATEST_BACKUP=$(ssh -p "$REMOTE_PORT" -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "ls -t $REMOTE_BACKUP_PATH/*.tar.gz 2>/dev/null | head -1")

    if [ -z "$LATEST_BACKUP" ]; then
        log ERROR "No backups found on remote server at $REMOTE_BACKUP_PATH"
        return 1
    fi

    BACKUP_FILENAME=$(basename "$LATEST_BACKUP")
    log INFO "Found latest backup: $BACKUP_FILENAME"

    # Check if we already have this backup
    if [ -f "$LOCAL_DAILY/$BACKUP_FILENAME" ]; then
        log INFO "Backup already exists locally, skipping download"
    else
        # Download the latest backup
        log INFO "Downloading backup..."
        if scp -P "$REMOTE_PORT" -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST:$LATEST_BACKUP" "$LOCAL_DAILY/"; then
            log INFO "Successfully downloaded: $BACKUP_FILENAME"
        else
            log ERROR "Failed to download backup"
            return 1
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
    log INFO "Removed $WEEKLY_DELETED old weekly backups"

    # Remove monthly backups older than retention period
    MONTHLY_DELETED=$(find "$LOCAL_MONTHLY" -name "*.tar.gz" -type f -mtime +$MONTHLY_RETENTION -delete -print | wc -l)
    log INFO "Removed $MONTHLY_DELETED old monthly backups"

    # Report backup counts
    DAILY_COUNT=$(find "$LOCAL_DAILY" -name "*.tar.gz" -type f | wc -l)
    WEEKLY_COUNT=$(find "$LOCAL_WEEKLY" -name "*.tar.gz" -type f | wc -l)
    MONTHLY_COUNT=$(find "$LOCAL_MONTHLY" -name "*.tar.gz" -type f | wc -l)

    log INFO "Current backup counts - Daily: $DAILY_COUNT, Weekly: $WEEKLY_COUNT, Monthly: $MONTHLY_COUNT"
    log INFO "=== Backup sync completed successfully ==="
}

# Start web UI in background
bashio::log.info "Starting web UI on port 8099..."
cd /app
python3 web_ui.py &
WEB_UI_PID=$!

# Wait for web UI to start
sleep 3

# Set up cron job
echo "$SCHEDULE /run_backup.sh" > /etc/crontabs/root

# Create wrapper script for cron
cat > /run_backup.sh << 'EOF'
#!/bin/bash
source /run.sh
sync_backup
EOF
chmod +x /run_backup.sh

bashio::log.info "Discourse Backup Sync started"
bashio::log.info "Web UI available at: http://[HOST]:8099"

if [ "$SSH_CONFIGURED" = "true" ]; then
    bashio::log.info "SSH configured - backups will sync automatically"
    bashio::log.info "Schedule: $SCHEDULE"
    bashio::log.info "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_PATH"
    bashio::log.info "Local storage: $LOCAL_BACKUP_BASE"
    bashio::log.info "Retention - Daily: ${DAILY_RETENTION}d, Weekly: ${WEEKLY_RETENTION}d, Monthly: ${MONTHLY_RETENTION}d"

    # Run initial sync
    sync_backup
else
    bashio::log.warning "SSH not configured. Please visit the web UI to complete setup."
fi

# Start cron
crond -f -l 2