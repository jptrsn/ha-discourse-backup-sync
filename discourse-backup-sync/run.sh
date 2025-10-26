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

# Set up SSH if configured
if [ "$SSH_CONFIGURED" = "true" ] && [ -f "$SSH_KEY_PATH" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    cp "$SSH_KEY_PATH" ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan -p "$REMOTE_PORT" -H "$REMOTE_HOST" >> ~/.ssh/known_hosts 2>/dev/null
fi

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
    echo "$SCHEDULE /backup.sh" > /etc/crontabs/root

    bashio::log.info "SSH configured - backups will sync automatically"
    bashio::log.info "Schedule: $SCHEDULE"
    bashio::log.info "Remote: $REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_PATH"
    bashio::log.info "Local storage: $LOCAL_BACKUP_BASE"
    bashio::log.info "Retention - Daily: ${DAILY_RETENTION}d, Weekly: ${WEEKLY_RETENTION}d, Monthly: ${MONTHLY_RETENTION}d"

    # Run initial sync
    /backup.sh

    # Start cron in background
    bashio::log.info "Starting cron daemon..."
    crond -l 2 &
fi

# Keep container running (wait for web UI process)
bashio::log.info "Add-on is running. Access the web UI to manage backups."
wait $WEB_UI_PID