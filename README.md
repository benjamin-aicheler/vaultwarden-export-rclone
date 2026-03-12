# Vaultwarden Export & Rclone Upload

This Dockerized tool allows you to automatically export your Vaultwarden (Bitwarden) vault as an unencrypted JSON file and securely upload it to any cloud storage backend supported by [rclone](https://rclone.org/).

## Features

- **Automated Export**: Uses the official `@bitwarden/cli` to securely log in, unlock, and export your vault.
- **Universal Storage**: Uses `rclone` under the hood, supporting 40+ cloud storage products (S3, WebDAV, SMB, Google Drive, OneDrive, Nextcloud, etc.).
- **Automatic Cleanup**: Rotates old backups automatically based on a configurable retention period.
- **Lightweight**: Built on Alpine Linux.

## Requirements

You will need the following information from your Vaultwarden / Bitwarden complete the setup:
1. Vaultwarden URL (`BW_HOST`)
2. Bitwarden API Key (Client ID `BW_CLIENTID` & Client Secret `BW_CLIENTSECRET`) - found in Account Settings -> Security -> Keys.
3. Master Password (`BW_PASSWORD`)

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `BW_HOST` | URL of your Vaultwarden instance (e.g., `https://vault.example.com`) | | Yes |
| `BW_CLIENTID` | Bitwarden API Client ID (`user.xxxxxxxx`) | | Yes |
| `BW_CLIENTSECRET` | Bitwarden API Client Secret | | Yes |
| `BW_PASSWORD` | Master password to unlock your vault | | Yes |
| `RCLONE_DEST` | Rclone destination string (e.g., `mysmb:vaultwarden`). Also configure any required `RCLONE_CONFIG_*` vars. | | Yes |
| `RCLONE_CONFIG_*` | Any Rclone configuration parameters (e.g. `RCLONE_CONFIG_MYSMB_TYPE=smb`) | | No |
| `CLEANUP_MIN_AGE` | Minimum age of backups to keep (default: `30d`). Evaluated based on rclone `--min-age`. | `30d` | No |
| `ARCHIVE_PASSWORD`| If set, the exported JSON will be compressed and encrypted into a `.7z` archive using this password and AES-256 encryption. | | No |
| `SMB_PATH` | *Deprecated.* Use `RCLONE_DEST` instead. | | No |

*Note: You must also pass your `rclone` backend configuration via environment variables (e.g., `RCLONE_CONFIG_MYREMOTE_TYPE`, `RCLONE_CONFIG_MYREMOTE_PROVIDER`, etc.) based on your desired storage format, or mount an `rclone.conf` file.*

## Usage Guide

The container is designed to run once, execute the export and upload, and then exit. It is perfect for scheduling via cron or a scheduler like [Ofelia](https://github.com/mcuadros/ofelia).

### 1. Example: Docker Compose with SMB (Samba/Windows Share)

```yaml
version: '3.8'

services:
  vaultwarden-backup:
    image: benjaminaicheler/vaultwarden-export-rclone:latest
    environment:
      # --- Vaultwarden Settings ---
      - BW_HOST=https://vault.example.com
      - BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      - BW_CLIENTSECRET=your_client_secret
      - BW_PASSWORD=YourMasterPassword123
      
      # --- Backup Settings ---
      - CLEANUP_MIN_AGE=30d
      - RCLONE_DEST=mysmb:vaultwarden
      
      # --- Rclone SMB Configuration ---
      - RCLONE_CONFIG_MYSMB_TYPE=smb
      - RCLONE_CONFIG_MYSMB_HOST=192.168.1.10
      - RCLONE_CONFIG_MYSMB_USER=your_smb_user
      - RCLONE_CONFIG_MYSMB_PASS=your_obfuscated_smb_password # Important! See rclone docs on 'rclone obscure'
      - RCLONE_CONFIG_MYSMB_DOMAIN=WORKGROUP # Optional
```

#### Rclone Backend Configuration

Use environment variables to configure Rclone backends dynamically without needing a configuration file.

**Example for an SMB backend:**
```bash
-e RCLONE_CONFIG_MYSMB_TYPE=smb \
-e RCLONE_CONFIG_MYSMB_HOST=192.168.1.100 \
-e RCLONE_CONFIG_MYSMB_USER=myuser \
-e RCLONE_CONFIG_MYSMB_PASS=mypassword \
-e RCLONE_DEST=mysmb:backup_folder
```

### Encryption and Archiving

If you wish to securely compress and password-protect your Vaultwarden export before uploading it, you can provide the `ARCHIVE_PASSWORD` environment variable.

```bash
docker run -d \
   # ... other environment variables ...
   -e ARCHIVE_PASSWORD="your-strong-archive-password" \
   vaulwarden-export-rclone
```

When this variable is provided, the script uses `7zip` to create an AES-256 encrypted `.7z` archive containing the vault export instead of uploading plain `.json` files.

**Restoring from an encrypted archive:**
You can use standard unarchiving tools like `7z` to extract the JSON locally:
```bash
7z x -p"your-strong-archive-password" vault-export-YYYY-MM-DD_HHMMSS.7z
```

### 2. Example: Running as a Cron Job

You can set it up via `crontab` on your host machine to run nightly.

Save your variables in a `.env` file (`/opt/vaultwarden-backup/.env`) and run:
**(Run the backup every day at 3:00 AM)**

```bash
0 3 * * * docker run --rm --env-file /opt/vaultwarden-backup/.env benjaminaicheler/vaultwarden-export-rclone:latest
```

## Security Considerations

- The container requires your **Master Password** and **API credentials** in plaintext as environment variables in order to perform an automated export.
- **WARNING: The exported JSON file is currently UNENCRYPTED.** Ensure your `rclone` destination is secure and access-controlled.
- Always ensure your `.env` files or `docker-compose.yml` configs are strictly secured (e.g., `chmod 600`) and owned by `root`/your admin user only.
- Consider utilizing a dedicated read-only/backup account in Vaultwarden if practical.

## License

This project is licensed under the Apache License 2.0. See the `LICENSE` file for details.
