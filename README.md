# Discourse Backup Sync - Home Assistant Add-on

This repository contains a Home Assistant add-on that automatically syncs backups from a remote Discourse server to your Home Assistant instance with configurable retention policies.

## Project Architecture

This is a **Home Assistant Add-on Repository** with the following structure:

```
ha-discourse-backup-sync/
├── .github/
│   └── workflows/
│       └── build.yml           # GitHub Actions for building multi-arch images
├── discourse-backup-sync/      # The add-on itself
│   ├── config.yaml             # Add-on configuration
│   ├── Dockerfile              # Container build instructions
│   ├── backup.sh               # Backup sync logic
│   ├── run.sh                  # Add-on startup script
│   ├── web_ui.py               # Flask web interface
│   ├── templates/              # HTML templates for web UI
│   └── README.md               # Add-on documentation (user-facing)
└── repository.json             # Repository metadata for Home Assistant
```

## How It Works

1. **Add-on Structure**: The `discourse-backup-sync` folder contains a complete Home Assistant add-on
2. **Repository Configuration**: The `repository.json` file makes this a valid Home Assistant add-on repository
3. **Multi-Architecture Support**: GitHub Actions automatically builds images for all supported architectures (aarch64, amd64, armhf, armv7, i386)
4. **Pre-built Images**: Images are published to GitHub Container Registry (ghcr.io) for faster installation

## Components

- **backup.sh**: Standalone script that handles the backup sync logic (SSH connection, download, retention management)
- **run.sh**: Startup script that initializes the add-on, starts the web UI, and sets up the cron schedule
- **web_ui.py**: Flask-based web interface for configuration and management
- **Dockerfile**: Builds the container with all necessary dependencies (SSH, Python, Flask, jq, etc.)

## For Users

📖 **[View the Add-on Documentation →](./discourse-backup-sync/README.md)**

The add-on documentation includes:
- Installation instructions
- Configuration guide
- Usage examples
- Troubleshooting tips

## For Developers

### Local Development

To build and test the add-on locally:

```bash
# Build for your architecture
docker build -t discourse-backup-sync ./discourse-backup-sync

# Run locally
docker run -p 8099:8099 discourse-backup-sync
```

### Building Multi-Arch Images

The GitHub Actions workflow automatically builds and publishes images when you push to the `main` branch or create a tag.

To trigger a build:
```bash
git tag v0.1.1
git push origin v0.1.1
```

### Making Changes

1. Modify files in `discourse-backup-sync/`
2. Update the version in `discourse-backup-sync/config.yaml`
3. Commit and push
4. GitHub Actions will automatically build and publish new images

## Installation

Add this repository to your Home Assistant add-on store:

```
https://github.com/jptrsn/ha-discourse-backup-sync
```

Then install the "Discourse Backup Sync" add-on from the add-on store.

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please open an issue or pull request.

## Support

- **Issues**: [GitHub Issues](https://github.com/jptrsn/ha-discourse-backup-sync/issues)
- **Documentation**: [Add-on README](./discourse-backup-sync/README.md)