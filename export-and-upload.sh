#!/bin/sh
set -e

# The files created here contain the vault in plaintext (until archived): keep
# them readable for root only instead of relying on the container being empty.
umask 077

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

# Validate the retention window before logging in, so a typo cannot fail the run
# after a backup has already been uploaded.
if ! printf '%s' "$CLEANUP_MIN_AGE" | grep -Eq '^[0-9]+[smhdwMy]$'; then
    echo "Error: CLEANUP_MIN_AGE must be a number followed by one unit, e.g. '30d', '12h' or '1w' (got '$CLEANUP_MIN_AGE')."
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
JSON_FILENAME="/tmp/vault-export-${TIMESTAMP}.json"
ARCHIVE_FILENAME="/tmp/vault-export-${TIMESTAMP}.7z"

# Determine final upload filename based on ARCHIVE_PASSWORD
if [ -n "$ARCHIVE_PASSWORD" ]; then
    UPLOAD_FILENAME="$ARCHIVE_FILENAME"
else
    UPLOAD_FILENAME="$JSON_FILENAME"
fi

# Register cleanup trap (runs on exit/error)
cleanup() {
    echo "Cleaning up local files and session..."
    rm -f "$JSON_FILENAME"
    rm -f "$ARCHIVE_FILENAME"
    bw logout || true
}
trap cleanup EXIT

# Perform Export
echo "Exporting vault to $JSON_FILENAME..."
bw export --output "$JSON_FILENAME" --format json --session "$BW_SESSION"

if [ ! -f "$JSON_FILENAME" ]; then
    echo "Error: Export failed, JSON file not created."
    exit 1
fi

# Optional Encryption
if [ -n "$ARCHIVE_PASSWORD" ]; then
    echo "ARCHIVE_PASSWORD is set. Encrypting JSON to $ARCHIVE_FILENAME..."
    # -p: set password
    # -mhe=on: encrypt archive header (hide file names inside archive)
    7z a -p"$ARCHIVE_PASSWORD" -mhe=on -t7z "$ARCHIVE_FILENAME" "$JSON_FILENAME" >/dev/null
    
    if [ ! -f "$ARCHIVE_FILENAME" ]; then
        echo "Error: Encryption failed, 7z archive not created."
        exit 1
    fi
    
    # Drop the plaintext copy now that it is archived. This is not a secure erase:
    # it removes the file from the live filesystem, the blocks may survive below
    # it (overlayfs/copy-on-write) and in an image commit of this container.
    rm -f "$JSON_FILENAME"
fi

# Upload
echo "Uploading to ${RCLONE_DEST}..."
rclone copy "$UPLOAD_FILENAME" "${RCLONE_DEST}"

# Retention Cleanup
# Both formats are rotated regardless of the current mode, so switching
# ARCHIVE_PASSWORD on or off cannot leave old plaintext exports behind.
# Ordered --filter rules (first match wins) keep the backup uploaded in this run
# out of the cleanup even if the remote reports an unusable modification time.
# The trailing "- *" is required: with "+" rules in place rclone includes every
# unmatched file, which would delete anything else living in the destination.
echo "Removing backups older than $CLEANUP_MIN_AGE..."
rclone delete "${RCLONE_DEST}" \
    --min-age "$CLEANUP_MIN_AGE" \
    --filter "- $(basename "$UPLOAD_FILENAME")" \
    --filter "+ vault-export-*.json" \
    --filter "+ vault-export-*.7z" \
    --filter "- *"

echo "Process complete."