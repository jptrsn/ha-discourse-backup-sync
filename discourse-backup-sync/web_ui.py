#!/usr/bin/env python3
"""Web UI for SSH configuration and settings"""

import os
import json
import subprocess
from flask import Flask, render_template, request, jsonify, Response
from werkzeug.middleware.proxy_fix import ProxyFix
import logging

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ADDON_OPTIONS_PATH = "/data/options.json"
CONFIG_PATH = "/data/config.json"
SSH_KEY_PATH = "/data/ssh_key"
SSH_PUB_KEY_PATH = "/data/ssh_key.pub"

# Default configuration
DEFAULT_CONFIG = {
    "remote_host": "",
    "remote_user": "",
    "remote_port": 22,
    "remote_backup_path": "/var/lib/docker/volumes/discourse_data/_data/backups/default",
    "backup_storage_path": "/backup/discourse",
    "daily_retention_days": 7,
    "weekly_retention_days": 90,
    "monthly_retention_days": 730,
    "schedule": "0 3 * * *"
}

# Add after_request handler to ensure JSON content-type
@app.after_request
def after_request(response):
    if request.path.startswith('/api/'):
        response.headers['Content-Type'] = 'application/json'
    return response

def load_addon_options():
    """Load Home Assistant add-on options"""
    try:
        with open(ADDON_OPTIONS_PATH, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load add-on options: {e}")
        return {}

def load_config():
    """Load add-on configuration"""
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, 'r') as f:
                return {**DEFAULT_CONFIG, **json.load(f)}
        return DEFAULT_CONFIG.copy()
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return DEFAULT_CONFIG.copy()

def save_config(config):
    """Save add-on configuration"""
    try:
        with open(CONFIG_PATH, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        logger.error(f"Failed to save config: {e}")
        return False

def generate_ssh_key():
    """Generate SSH key pair"""
    try:
        # Remove existing keys
        for path in [SSH_KEY_PATH, SSH_PUB_KEY_PATH]:
            if os.path.exists(path):
                os.remove(path)

        # Generate new key
        result = subprocess.run(
            ['ssh-keygen', '-t', 'ed25519', '-f', SSH_KEY_PATH, '-N', '', '-q'],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            logger.error(f"ssh-keygen failed: {result.stderr}")
            return False

        os.chmod(SSH_KEY_PATH, 0o600)
        return True
    except Exception as e:
        logger.error(f"Failed to generate SSH key: {e}")
        return False

def setup_ssh_connection(host, port, user, password):
    """Setup SSH connection by copying public key to remote server"""
    try:
        # Read public key
        with open(SSH_PUB_KEY_PATH, 'r') as f:
            pub_key = f.read().strip()

        logger.info(f"Attempting to setup SSH for {user}@{host}:{port}")
        logger.info(f"Public key fingerprint: {pub_key[:50]}...")
        logger.info(f"Private key exists: {os.path.exists(SSH_KEY_PATH)}")

        # Check key permissions
        if os.path.exists(SSH_KEY_PATH):
            stat_info = os.stat(SSH_KEY_PATH)
            logger.info(f"Private key permissions: {oct(stat_info.st_mode)}")

        # Use ssh-keyscan to add host key
        try:
            result = subprocess.run(
                ['ssh-keyscan', '-p', str(port), '-H', host],
                capture_output=True,
                text=True,
                check=True,
                timeout=10
            )
            logger.info("SSH keyscan completed")
        except Exception as e:
            logger.warning(f"SSH keyscan failed (non-fatal): {e}")

        # Alternative method: Use sshpass to directly append the key
        logger.info("Using sshpass method to copy key...")

        # Read the public key
        with open(SSH_PUB_KEY_PATH, 'r') as f:
            pub_key_content = f.read().strip()

        # Use sshpass and ssh to append the key
        cmd = [
            'sshpass', '-p', password,
            'ssh', '-p', str(port),
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null',
            f'{user}@{host}',
            f'mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "{pub_key_content}" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo "Key added successfully"'
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        logger.info(f"sshpass return code: {result.returncode}")
        logger.info(f"sshpass stdout: {result.stdout}")
        logger.info(f"sshpass stderr: {result.stderr}")

        if result.returncode != 0:
            logger.error(f"sshpass method failed")
            return False, f"Failed to copy SSH key: {result.stderr or result.stdout}"

        if "Key added successfully" not in result.stdout:
            logger.warning("Key addition command completed but success message not found")

        # Give the server a moment to process
        import time
        time.sleep(2)

        # Test the connection
        logger.info("Testing SSH connection...")
        test_result = subprocess.run(
            ['ssh', '-v', '-p', str(port), '-i', SSH_KEY_PATH, '-o', 'BatchMode=yes',
             '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=10',
             '-o', 'IdentitiesOnly=yes',
             f'{user}@{host}', 'echo', 'success'],
            capture_output=True,
            text=True,
            timeout=15
        )

        logger.info(f"SSH test return code: {test_result.returncode}")
        logger.info(f"SSH test stdout: {test_result.stdout}")
        logger.info(f"SSH test stderr: {test_result.stderr}")

        if test_result.returncode != 0:
            logger.error(f"SSH test connection failed: {test_result.stderr}")
            return False, f"Key was copied but test connection failed: {test_result.stderr}"

        return True, "SSH configured successfully"

    except subprocess.TimeoutExpired:
        logger.error("Connection timeout during SSH setup")
        return False, "Connection timeout"
    except Exception as e:
        logger.error(f"Failed to setup SSH: {e}", exc_info=True)
        return False, str(e)

@app.route('/')
def index():
    """Main configuration page"""
    config = load_config()
    addon_options = load_addon_options()
    ssh_configured = os.path.exists(SSH_KEY_PATH)

    return render_template('index.html',
                         config=config,
                         addon_options=addon_options,
                         ssh_configured=ssh_configured)

@app.route('/api/config', methods=['GET'])
def get_config():
    """Get current configuration"""
    config = load_config()
    return jsonify({
        **config,
        'ssh_configured': os.path.exists(SSH_KEY_PATH)
    })

@app.route('/api/config', methods=['POST'])
def update_config():
    """Update configuration"""
    try:
        data = request.get_json()
        config = load_config()

        # Update config fields
        for key in ['remote_host', 'remote_user', 'remote_port', 'remote_backup_path',
                    'backup_storage_path', 'daily_retention_days', 'weekly_retention_days',
                    'monthly_retention_days', 'schedule']:
            if key in data:
                config[key] = data[key]

        if save_config(config):
            return jsonify({'success': True, 'message': 'Configuration saved'})
        else:
            return jsonify({'success': False, 'message': 'Failed to save configuration'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/setup-ssh', methods=['POST'])
def setup_ssh():
    """Setup SSH authentication"""
    try:
        data = request.get_json()
    except Exception as e:
        logger.error(f"Failed to parse JSON: {e}")
        return jsonify({'success': False, 'message': 'Invalid JSON data'}), 400

    host = data.get('host')
    port = data.get('port', 22)
    user = data.get('user')
    password = data.get('password')

    if not all([host, user, password]):
        return jsonify({'success': False, 'message': 'Missing required fields'}), 400

    logger.info(f"Setting up SSH for {user}@{host}:{port}")

    # Save connection details to config
    config = load_config()
    config['remote_host'] = host
    config['remote_user'] = user
    config['remote_port'] = port
    save_config(config)

    # Generate SSH key if it doesn't exist
    if not os.path.exists(SSH_KEY_PATH):
        if not generate_ssh_key():
            return jsonify({'success': False, 'message': 'Failed to generate SSH key'}), 500

    # Setup SSH connection
    success, message = setup_ssh_connection(host, port, user, password)

    if success:
        return jsonify({'success': True, 'message': message})
    else:
        return jsonify({'success': False, 'message': message}), 500

@app.route('/api/test-connection', methods=['POST'])
def test_connection():
    """Test SSH connection"""
    config = load_config()
    host = config.get('remote_host')
    port = config.get('remote_port', 22)
    user = config.get('remote_user')

    if not all([host, user]):
        return jsonify({'success': False, 'message': 'Missing server configuration'}), 400

    if not os.path.exists(SSH_KEY_PATH):
        return jsonify({'success': False, 'message': 'SSH key not configured'}), 400

    try:
        result = subprocess.run(
            ['ssh', '-p', str(port), '-i', SSH_KEY_PATH, '-o', 'BatchMode=yes',
             '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
             f'{user}@{host}', 'echo', 'success'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            return jsonify({'success': True, 'message': 'Connection successful'})
        else:
            return jsonify({'success': False, 'message': f'Connection failed: {result.stderr}'}), 500

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/test-backup-path', methods=['POST'])
def test_backup_path():
    """Test if backup path exists and list recent backups"""
    config = load_config()
    host = config.get('remote_host')
    port = config.get('remote_port', 22)
    user = config.get('remote_user')
    backup_path = config.get('remote_backup_path')

    if not all([host, user, backup_path]):
        return jsonify({'success': False, 'message': 'Missing configuration'}), 400

    if not os.path.exists(SSH_KEY_PATH):
        return jsonify({'success': False, 'message': 'SSH key not configured'}), 400

    try:
        # List backups in the path
        result = subprocess.run(
            ['ssh', '-p', str(port), '-i', SSH_KEY_PATH, '-o', 'BatchMode=yes',
             '-o', 'ConnectTimeout=5', '-o', 'StrictHostKeyChecking=no',
             f'{user}@{host}', f'ls -lh {backup_path}/*.tar.gz 2>/dev/null | tail -5'],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0 and result.stdout.strip():
            backups = result.stdout.strip().split('\n')
            return jsonify({
                'success': True,
                'message': f'Found {len(backups)} recent backup(s)',
                'backups': backups
            })
        else:
            return jsonify({'success': False, 'message': 'No backups found or path does not exist'}), 404

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/reset-ssh', methods=['POST'])
def reset_ssh():
    """Reset SSH configuration"""
    try:
        # Remove SSH keys
        for path in [SSH_KEY_PATH, SSH_PUB_KEY_PATH]:
            if os.path.exists(path):
                os.remove(path)

        return jsonify({'success': True, 'message': 'SSH configuration reset'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/list-backups', methods=['GET'])
def list_backups():
    """List all local backups"""
    try:
        config = load_config()
        base_path = config.get('backup_storage_path', '/backup/discourse')

        backups = []

        for backup_type in ['daily', 'weekly', 'monthly']:
            path = os.path.join(base_path, backup_type)
            if os.path.exists(path):
                for filename in os.listdir(path):
                    if filename.endswith('.tar.gz'):
                        filepath = os.path.join(path, filename)
                        stat = os.stat(filepath)
                        backups.append({
                            'filename': filename,
                            'type': backup_type,
                            'size': stat.st_size,
                            'created': stat.st_mtime,
                            'path': filepath
                        })

        # Sort by creation time, newest first
        backups.sort(key=lambda x: x['created'], reverse=True)

        return jsonify({'success': True, 'backups': backups})
    except Exception as e:
        logger.error(f"Failed to list backups: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/delete-backup', methods=['POST'])
def delete_backup():
    """Delete a specific backup"""
    try:
        data = request.get_json()
        filepath = data.get('filepath')

        if not filepath:
            return jsonify({'success': False, 'message': 'No filepath provided'}), 400

        # Security check: ensure path is within backup directory
        config = load_config()
        base_path = config.get('backup_storage_path', '/backup/discourse')

        if not filepath.startswith(base_path):
            return jsonify({'success': False, 'message': 'Invalid path'}), 403

        if os.path.exists(filepath):
            os.remove(filepath)
            logger.info(f"Deleted backup: {filepath}")
            return jsonify({'success': True, 'message': 'Backup deleted successfully'})
        else:
            return jsonify({'success': False, 'message': 'Backup file not found'}), 404

    except Exception as e:
        logger.error(f"Failed to delete backup: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/manual-sync', methods=['POST'])
def manual_sync():
    """Trigger a manual backup sync"""
    try:
        config = load_config()

        if not os.path.exists(SSH_KEY_PATH):
            return jsonify({'success': False, 'message': 'SSH not configured'}), 400

        # Run the backup script
        result = subprocess.run(
            ['/backup.sh'],
            capture_output=True,
            text=True,
            timeout=300
        )

        if result.returncode == 0:
            return jsonify({
                'success': True,
                'message': 'Backup sync completed successfully',
                'output': result.stdout
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Backup sync failed',
                'error': result.stderr
            }), 500

    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Backup sync timed out'}), 500
    except Exception as e:
        logger.error(f"Manual sync failed: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8099, debug=False)