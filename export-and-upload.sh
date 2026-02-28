#!/bin/sh
set -e

# Configuration
CLEANUP_MIN_AGE=${CLEANUP_MIN_AGE:-"30d"}

echo "Starting Vaultwarden export..."

# Validation
if [ -z "$BW_HOST" ] || [ -z "$BW_PASSWORD" ] || [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
  echo "Error: BW_HOST, BW_PASSWORD, BW_CLIENTID, or BW_CLIENTSECRET not set."
  exit 1
fi

if [ -n "$SMB_PATH" ] && [ -z "$RCLONE_DEST" ]; then
    echo "Warning: SMB_PATH is deprecated. Please use RCLONE_DEST instead (e.g., 'mysmb:vaultwarden' and configure the backend via RCLONE_CONFIG_* environment variables). Falling back to SMB_PATH for backward compatibility."
    RCLONE_DEST=":smb:${SMB_PATH}"
fi

if [ -z "$RCLONE_DEST" ]; then
    echo "Error: RCLONE_DEST is not set."
    exit 1
fi

# Authentication
bw config server "$BW_HOST"
echo "Logging in to $BW_HOST..."
bw login --apikey

# Unlock Vault
echo "Unlocking vault..."
export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)

if [ -z "$BW_SESSION" ]; then
    echo "Error: Unlock failed. Check BW_PASSWORD."
    exit 1
fi

# Setup Export
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
FILENAME="/tmp/vault-export-${TIMESTAMP}.json"

# Register cleanup trap (runs on exit/error)
cleanup() {
    echo "Cleaning up local files and session..."
    rm -f "$FILENAME"
    bw logout || true
}
trap cleanup EXIT

# Perform Export
echo "Exporting vault to $FILENAME..."
bw export --output "$FILENAME" --format json --session "$BW_SESSION"

if [ ! -f "$FILENAME" ]; then
    echo "Error: Export failed, file not created."
    exit 1
fi

# Upload
echo "Uploading to ${RCLONE_DEST}..."
rclone copy "$FILENAME" "${RCLONE_DEST}"

# Retention Cleanup
echo "Removing backups older than $CLEANUP_MIN_AGE..."
rclone delete "${RCLONE_DEST}" --min-age "$CLEANUP_MIN_AGE" --include "vault-export-*.json"

echo "Process complete."