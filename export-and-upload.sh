#!/bin/sh
set -e # Exit immediately if any command fails

# 1. Set default for cleanup
CLEANUP_MIN_AGE=${CLEANUP_MIN_AGE:-"30d"}

echo "Starting Vaultwarden export..."

# 2. Validate environment variables
if [ -z "$BW_HOST" ] || [ -z "$BW_PASSWORD" ] || [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
  echo "Error: BW_HOST, BW_PASSWORD, BW_CLIENTID, or BW_CLIENTSECRET not set."
  exit 1
fi
if [ -z "$SMB_PATH" ]; then
    echo "Error: SMB_PATH is not set."
    exit 1
fi

# 3. Log in (Authenticate)
bw config server $BW_HOST
echo "Logging in to $BW_HOST using API Key..."
bw login --apikey

# 4. Unlock (Get Session Token)
echo "Unlocking vault to get session token..."
export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)

if [ -z "$BW_SESSION" ]; then
    echo "Error: Unlock FAILED. BW_SESSION is empty."
    echo "This almost always means your BW_PASSWORD (master password) is incorrect."
    exit 1
fi
echo "Vault unlocked. Session token acquired."

# 5. Export (Using the Session Token)
FILENAME="/tmp/vault-export-$(date +%Y-%m-%d).json"
echo "Exporting vault to $FILENAME..."
bw export --output $FILENAME --format json --session "$BW_SESSION"

# 6. Check for file
if [ ! -f "$FILENAME" ]; then
    echo "---"
    echo "Error: Export FAILED. The file '$FILENAME' was not created."
    echo "---"
    exit 1
fi
echo "Export complete."

# --- THIS IS THE FIX ---
# 7. Upload with rclone
echo "Starting rclone upload to SMB..."
# No flags needed. rclone reads RCLONE_SMB_HOST,
# RCLONE_SMB_USER, and RCLONE_SMB_PASS from the environment.
rclone copy $FILENAME ":smb:${SMB_PATH}"
echo "Upload complete."

# 8. Clean up old backups
echo "Cleaning up backups older than $CLEANUP_MIN_AGE..."
# No flags needed here either.
rclone delete ":smb:${SMB_PATH}" --min-age $CLEANUP_MIN_AGE
echo "Cleanup complete."