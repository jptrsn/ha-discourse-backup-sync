# Discourse Backup Sync - Home Assistant Add-on

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armhf Architecture][armhf-shield]
![Supports armv7 Architecture][armv7-shield]
![Supports i386 Architecture][i386-shield]

Automatically sync and manage backups from your Discourse forum with intelligent retention policies.

## About

This add-on connects to your remote Discourse server via SSH, downloads the latest backup, and manages retention with three tiers:

- **Daily backups**: Kept for a configurable number of days (default: 7 days)
- **Weekly backups**: Kept for a configurable number of days (default: 90 days / 3 months)
- **Monthly backups**: Kept for a configurable number of days (default: 730 days / 2 years)

Weekly backups are created every Sunday, and monthly backups are created on the 1st of each month.

## Key Features

- **Automatic SSH Setup** - Enter your password once, we handle the rest
- **Smart Backup Management** - Three-tier retention (daily, weekly, monthly)
- **Flexible Scheduling** - Use cron syntax to customize when backups sync

## Installation

1. **Add this repository** to your Home Assistant add-on store:
   - Go to **Settings → Add-ons → Add-on Store**
   - Click the menu (⋮) → **Repositories**
   - Add: `https://github.com/jptrsn/ha-discourse-backup-sync`

2. **Install** the "Discourse Backup Sync" add-on

3. **Start** the add-on

4. **Open Web UI** - Click "Open Web UI" button

5. **Configure everything through the web UI** - No YAML editing required!

## Quick Start Guide

### Step 1: Install and Start

1. Install the add-on from the add-on store
2. Start the add-on
3. Click "Open Web UI"

### Step 2: Configure SSH key (Setup Tab)

1. Enter your Discourse server hostname/IP
2. Enter SSH port (usually 22)
3. Enter SSH username (usually `root`)
4. Enter your SSH password
5. Click "Setup SSH Authentication"

The add-on will:
- Generate an SSH key pair
- Copy the public key to your server
- Test the connection
- Save your settings

### Step 3: Configure Backup Settings (Settings Tab)

1. **Find your remote backup path** by running this on your Discourse server:
   ```bash
   docker volume inspect discourse_data | grep Mountpoint
   ```
   Then add `/backups/default` to the path shown.

   Example: If Mountpoint is `/var/lib/docker/volumes/root_discourse_data/_data`,
   your path is: `/var/lib/docker/volumes/root_discourse_data/_data/backups/default`

2. **Set your local storage path** (where backups are stored on Home Assistant)

3. **Configure backup schedule** using cron format (default: `0 3 * * *` = 3 AM daily)

4. **Set retention periods**:
   - Daily backups: how many days to keep
   - Weekly backups: how many days to keep
   - Monthly backups: how many days to keep

5. Click "Save Settings"

6. Click "Test Backup Path" to verify backups are accessible

### Step 4: Done!

Your backups will now sync automatically according to the schedule. Check the Status tab anytime to test your connection!

## Web UI Configuration

### Setup Tab
- Initial SSH configuration
- Enter server details and password once
- Automatic SSH key generation and deployment
- View configured server details after setup

### Settings Tab
- Configure remote backup path
- Set local backup storage path
- Configure backup schedule (cron syntax)
- Set retention periods for daily/weekly/monthly backups
- Test backup path to see recent backups on your server

### Status Tab
- View connection status and configuration
- Test SSH connection anytime
- See current schedule
- Reset SSH configuration if needed

## Home Assistant Configuration (Optional)

Only one setting in the Home Assistant configuration tab (everything else is in the web UI):

```yaml
log_level: "info"  # Logging verbosity (debug/info/warning/error)
```

Everything else (server details, paths, schedule, retention) is configured through the web UI!

## Storage Requirements

Discourse backups can be quite large (especially with uploads). Make sure you have sufficient storage on your Home Assistant server.

**Estimated Storage Needed:**
- Small forum (< 1GB backups): ~50GB recommended
- Medium forum (1-5GB backups): ~200GB recommended
- Large forum (> 5GB backups): ~500GB+ recommended

The add-on stores backups in three folders (path configurable via web UI):
- `[storage_path]/daily/` - Daily backups
- `[storage_path]/weekly/` - Weekly backups
- `[storage_path]/monthly/` - Monthly backups

## Scheduling

The schedule uses standard cron syntax (configured in Settings tab):

```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-7, Sunday = 0 or 7)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

**Common Examples:**
- `0 3 * * *` - Every day at 3:00 AM (default)
- `0 */6 * * *` - Every 6 hours
- `0 2 * * 0` - Every Sunday at 2:00 AM
- `0 4 1 * *` - First day of every month at 4:00 AM

## Troubleshooting

### SSH Setup Fails

**Error: "Connection timeout"**
- Check that your server is reachable from Home Assistant
- Verify the hostname/IP is correct
- Check firewall settings

**Error: "Authentication failed"**
- Verify username and password are correct
- Ensure the user has SSH access enabled
- Check if password authentication is enabled in SSH config

### No Backups Found

**Error: "No backups found on remote server"**

1. Use the "Test Backup Path" button in the Settings tab
2. Verify the backup path is correct
3. SSH into your server and check:
   ```bash
   ls -lh /var/lib/docker/volumes/root_discourse_data/_data/backups/default/
   ```
4. Ensure Discourse is actually creating backups (check `/admin/backups` in Discourse)
5. Verify the SSH user has permission to access the backup directory

### Permission Issues

If you get permission denied errors:

```bash
# On your Discourse server, check permissions
ls -ld /var/lib/docker/volumes/root_discourse_data/_data/backups/default/

# Fix if needed (as root)
chmod 755 /var/lib/docker/volumes/root_discourse_data/_data/backups/default/
```

### Backups Not Syncing

1. Check the add-on logs for errors
2. Use the "Test Connection" button in the Status tab
3. Verify the schedule is correct in Settings tab
4. Ensure the add-on is running
5. Check that you have enough storage space

### Add-on Won't Start

1. Check the add-on logs
2. Verify you have the latest version
3. Try restarting Home Assistant
4. If issues persist, reset the add-on by removing `/data/config.json` and `/data/ssh_key*` files

## Advanced Usage

### Manual Backup Trigger

Access the add-on container and run:

```bash
/run_backup.sh
```

This will immediately sync the latest backup from your Discourse server.

### Custom Storage Location

Configure your storage location in the Settings tab of the web UI. You can use:
- Local paths: `/backup/discourse`
- Network storage: `/mnt/nas/discourse-backups` (mount first in Home Assistant)
- Any writable path accessible to Home Assistant

### Multiple Discourse Servers

To backup multiple Discourse servers, install multiple instances of this add-on with different configurations. Each will maintain its own SSH keys and backup storage.

## Security Notes

- SSH keys are stored securely in `/data/ssh_key`
- Passwords are **never stored** - only used once during initial setup
- SSH connections use key-based authentication only
- All communications are encrypted via SSH
- Web UI is only accessible within your Home Assistant network

## How It Works

1. **Scheduled Sync**: At your configured schedule, the add-on connects to your Discourse server using the SSH key you created using the web UI.
2. **Download Latest**: Downloads the most recent backup file
3. **Smart Storage**:
   - Stores in daily folder
   - Copies to weekly folder every Sunday
   - Copies to monthly folder on the 1st of each month
4. **Automatic Cleanup**: Removes old backups based on your retention settings

## Support

For issues, questions, or contributions:
- [Report a Bug](https://github.com/jptrsn/ha-discourse-backup-sync/issues)
- [Request a Feature](https://github.com/jptrsn/ha-discourse-backup-sync/issues)
- [View Documentation](https://github.com/jptrsn/ha-discourse-backup-sync)

## License

MIT License - feel free to use and modify!

---

Made with ❤️ for the Home Assistant and Discourse communities

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armhf-shield]: https://img.shields.io/badge/armhf-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
[i386-shield]: https://img.shields.io/badge/i386-yes-green.svg