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
services:
  vaultwarden-backup:
    image: benjaminaicheler/vaultwarden-export-rclone:latest
    # Mount your custom CA certificate so the container trusts your 
    # self-hosted Vaultwarden instance (fixes "self signed certificate" errors).
    #volumes:
    #  - ./ca.crt:/etc/ssl/custom-ca/ca.crt:ro
    environment:
      # --- Vaultwarden Settings ---
      - BW_HOST=https://vault.example.com
      - BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      - BW_CLIENTSECRET=your_client_secret
      - BW_PASSWORD=YourMasterPassword123
      # Point Node.js to the mounted CA certificate
      #- NODE_EXTRA_CA_CERTS=/etc/ssl/custom-ca/ca.crt
      
      # --- Backup Settings ---
      - CLEANUP_MIN_AGE=30d
      - RCLONE_DEST=mysmb:vaultwarden
      
      # --- Rclone SMB Configuration ---
      - RCLONE_CONFIG_MYSMB_TYPE=smb
      - RCLONE_CONFIG_MYSMB_HOST=192.168.1.10
      - RCLONE_CONFIG_MYSMB_USER=your_smb_user
      # IMPORTANT: This must be an OBSCURED password, not plain text.
      # Run 'rclone obscure "yourpassword"' to generate this string.
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

### 1.1 Example: Kubernetes with SMB (Samba/Windows Share)

I'm assuming you created the used secrets (`vaultwarden-export-creds` and `smb-export-creds`).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vaultwarden-export-smb
  namespace: vaultwarden
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          
          #volumes:
          #  - name: ssl-certs
          #    secret:
          #      secretName: certificate-secret 
          
          containers:
            - name: vault-exporter
              image: benjaminaicheler/vaultwarden-export-rclone:latest
              
              #volumeMounts:
              #  - name: ssl-certs
              #    readOnly: true
              #    mountPath: /etc/ssl/k3s-certs
              
              env:
                #- name: NODE_EXTRA_CA_CERTS
                #  value: /etc/ssl/k3s-certs/ca.crt
                
                # --- Bitwarden Credentials ---
                - name: BW_HOST
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_HOST
                - name: BW_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_PASSWORD
                - name: BW_CLIENTID
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_CLIENTID
                - name: BW_CLIENTSECRET
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_CLIENTSECRET
                
                # --- Backup Settings ---
                - name: CLEANUP_MIN_AGE
                  value: "30d"
                - name: RCLONE_DEST
                  value: "mysmb:vaultwarden"
                
                # --- Rclone SMB Configuration ---
                - name: RCLONE_CONFIG_MYSMB_TYPE
                  value: "smb"
                - name: RCLONE_CONFIG_MYSMB_HOST
                  value: "192.168.1.10"
                - name: RCLONE_CONFIG_MYSMB_USER
                  valueFrom:
                    secretKeyRef:
                      name: smb-export-creds
                      key: RCLONE_SMB_USER # Key in secret
                - name: RCLONE_CONFIG_MYSMB_PASS
                  valueFrom:
                    secretKeyRef:
                      name: smb-export-creds
                      key: RCLONE_SMB_PASS # Key in secret
                - name: RCLONE_CONFIG_MYSMB_DOMAIN
                  value: "WORKGROUP"
```

### 1.2 LEGACY 1.x Version Example: Docker Compose with SMB (Samba/Windows Share) (still supported in 2.x)

```
services:
  vaultwarden-backup:
    # Replace with your actual image tag
    image: benjaminaicheler/vaultwarden-export-rclone:latest
    container_name: vaultwarden-backup

    # Mount your custom CA certificate so the container trusts your 
    # self-hosted Vaultwarden instance (fixes "self signed certificate" errors).
    #volumes:
    #  - ./ca.crt:/etc/ssl/custom-ca/ca.crt:ro

    environment:
      # -------------------------------------------------------
      # 1. Vaultwarden Connection & Auth
      # -------------------------------------------------------
      - BW_HOST=https://vault.yourdomain.com
      
      # API Keys (Get these from Settings > Account Security > View API Key)
      - BW_CLIENTID=user.xxxx-xxxx-xxxx-xxxx
      - BW_CLIENTSECRET=yyyy_yyyy_yyyy
      
      # Master Password (Required to unlock/decrypt the vault for export)
      - BW_PASSWORD=YourSuperSecretMasterPassword

      # Point Node.js to the mounted CA certificate
      #- NODE_EXTRA_CA_CERTS=/etc/ssl/custom-ca/ca.crt

      # -------------------------------------------------------
      # 2. SMB / Rclone Configuration
      # -------------------------------------------------------
      - RCLONE_SMB_HOST=192.168.1.50
      - RCLONE_SMB_USER=backup_user
      
      # IMPORTANT: This must be an OBSCURED password, not plain text.
      # Run 'rclone obscure "yourpassword"' to generate this string.
      - RCLONE_SMB_PASS=v1;000000000000000000000000000000000000;
      
      # The specific sub-folder on the SMB share to save files to
      - SMB_PATH=Backups/Vaultwarden

      # -------------------------------------------------------
      # 3. Retention Policy
      # -------------------------------------------------------
      # Automatically delete backup files on the share older than this
      - CLEANUP_MIN_AGE=30d
```

### 1.3 LEGACY 1.x Version Example: Kubernetes with SMB (Samba/Windows Share) (still supported in 2.x)

I'm assuming you created the used secrets.

```
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vaultwarden-export-smb
  namespace: vaultwarden
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          
          #volumes:
          #  - name: ssl-certs
          #    secret:
          #      secretName: certificate-secret 
          
          containers:
            - name: vault-exporter
              image: benjaminaicheler/vaultwarden-export-rclone:latest
              
              #volumeMounts:
              #  - name: ssl-certs
              #    readOnly: true
              #    mountPath: /etc/ssl/k3s-certs
              
              env:
                #- name: NODE_EXTRA_CA_CERTS
                #  value: /etc/ssl/k3s-certs/ca.crt
                
                # --- Bitwarden Credentials ---
                - name: BW_HOST
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_HOST
                - name: BW_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_PASSWORD
                - name: BW_CLIENTID
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_CLIENTID
                - name: BW_CLIENTSECRET
                  valueFrom:
                    secretKeyRef:
                      name: vaultwarden-export-creds
                      key: BW_CLIENTSECRET
                
                # --- SMB Config ---
                # This is the one custom var the script still needs
                - name: SMB_PATH
                  value: "Your/Backup/Share/Path"
                
                # --- rclone Native Env Vars ---
                - name: RCLONE_SMB_HOST
                  value: "YOUR_SERVER_IP_OR_HOSTNAME"
                - name: RCLONE_SMB_USER
                  valueFrom:
                    secretKeyRef:
                      name: smb-export-creds
                      key: RCLONE_SMB_USER # Key in secret
                - name: RCLONE_SMB_PASS
                  valueFrom:
                    secretKeyRef:
                      name: smb-export-creds
                      key: RCLONE_SMB_PASS # Key in secret
                
                # --- Retention Policy ---
                - name: CLEANUP_MIN_AGE
                  value: "30d"
```

### 2. Example: Running as a Cron Job

You can set it up via `crontab` on your host machine to run nightly.

Save your variables in a `.env` file (`/opt/vaultwarden-backup/.env`) and run:
**(Run the backup every day at 3:00 AM)**

```bash
0 3 * * * docker run --rm --env-file /opt/vaultwarden-backup/.env benjaminaicheler/vaultwarden-export-rclone:latest
```
See Compose Example for including self-signed Certificates.

## Security Considerations

- The container requires your **Master Password** and **API credentials** in plaintext as environment variables in order to perform an automated export.
- **Security Warning:** By default, the exported JSON file is **UNENCRYPTED**. We highly recommend setting the `ARCHIVE_PASSWORD` environment variable to encrypt your backup before it is uploaded. Regardless, ensure your `rclone` destination is secure.
- Always ensure your `.env` files or `docker-compose.yml` configs are strictly secured (e.g., `chmod 600`) and owned by `root`/your admin user only.
- Consider utilizing a dedicated read-only/backup account in Vaultwarden if practical.

### Third-Party Licenses

This Docker image is distributed as a bundled environment and contains third-party software subject to their respective open-source licenses, including copyleft licenses. When using or redistributing this image, you must comply with the terms of these licenses:

* **[Node.js](https://github.com/nodejs/node):** MIT License
* **[Alpine Linux](https://alpinelinux.org/):** Various Open-Source Licenses (including MIT and GPLv2)
* **[Rclone](https://github.com/rclone/rclone):** MIT License
* **[Bitwarden CLI (bw-cli)](https://github.com/bitwarden/clients/tree/master/apps/cli):** GPLv3
* **[7-Zip](https://www.7-zip.org/):** GNU LGPL (with unRAR restriction for RAR code)
<br />
<br />
**GPL Source Code Provision:**
The GPL-licensed components within this image (such as Alpine's core utilities, 7-zip, and the Bitwarden CLI) are distributed as unmodified, pre-compiled binaries obtained from their upstream maintainers. This constitutes "mere aggregation". To comply with the GPLv2 and GPLv3 requirements, the original source code for these components can be accessed directly via the upstream repository links provided above.
