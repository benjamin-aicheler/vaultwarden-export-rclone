# Vaultwarden Export & Rclone Upload

This Dockerized tool exports your Vaultwarden (Bitwarden) vault as JSON, optionally packs it into a password-protected `.7z` archive, checks the result and uploads it to any storage backend supported by [rclone](https://rclone.org/).

## Features

- **Automated Export**: Uses the official `@bitwarden/cli` to securely log in, unlock, and export your vault.
- **Universal Storage**: Uses `rclone` under the hood, supporting 40+ cloud storage products (S3, WebDAV, SMB, Google Drive, OneDrive, Nextcloud, etc.).
- **Checked Before Upload**: The exported JSON is parsed and, in archive mode, the `.7z` is verified with `7z t` before anything leaves the container — a broken export never replaces a working backup.
- **Automatic Cleanup**: Rotates `.json` **and** `.7z` backups older than `CLEANUP_MIN_AGE`; the backup written by the current run is always kept.
- **Lightweight**: Built on Alpine Linux.

## Requirements

You will need the following information from your Vaultwarden / Bitwarden to complete the setup:
1. Vaultwarden URL (`BW_HOST`)
2. Bitwarden API Key (Client ID `BW_CLIENTID` & Client Secret `BW_CLIENTSECRET`) - found in Account Settings -> Security -> Keys.
3. Master Password (`BW_PASSWORD`)

### Image tags

Images are published to Docker Hub (`benjaminaicheler/vaultwarden-export-rclone`) and to `ghcr.io/benjamin-aicheler/vaultwarden-export-rclone`, both as multi-arch images (`linux/amd64`, `linux/arm64`):

| Tag | Meaning |
|-----|---------|
| `latest` | Last release. Only moved by a `v*` tag, so it never jumps between releases by itself. |
| `dev` | Current `main` on every push. Built and smoke-tested, but not a release. |
| `sha-<short>` | One specific commit, for pinning a deployment. |

Use `latest` for scheduled backups and pin `sha-…` if you need the exact build to be reproducible.

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `BW_HOST` | URL of your Vaultwarden instance (e.g., `https://vault.example.com`) | | Yes |
| `BW_CLIENTID` | Bitwarden API Client ID (`user.xxxxxxxx`) | | Yes |
| `BW_CLIENTSECRET` | Bitwarden API Client Secret | | Yes |
| `BW_PASSWORD` | Master password to unlock your vault | | Yes |
| `RCLONE_DEST` | Rclone destination string (e.g., `mysmb:vaultwarden`). Also configure any required `RCLONE_CONFIG_*` vars. | | Yes |
| `RCLONE_CONFIG_*` | Any Rclone configuration parameters (e.g. `RCLONE_CONFIG_MYSMB_TYPE=smb`) | | No |
| `CLEANUP_MIN_AGE` | Number plus unit (`30d`, `12h`, `1w`, `2M`, `1y`), validated before the run starts. Backups older than this are deleted via rclone `--min-age`; both `.json` and `.7z` backups are rotated. | `30d` | No |
| `ARCHIVE_PASSWORD`| If set, the exported JSON will be compressed and encrypted into a `.7z` archive using this password and AES-256 encryption. | | No |
| `SMB_PATH` | *Deprecated.* Use `RCLONE_DEST` instead. | | No |

*Note: You must also pass your `rclone` backend configuration via environment variables (e.g., `RCLONE_CONFIG_MYREMOTE_TYPE`, `RCLONE_CONFIG_MYREMOTE_PROVIDER`, etc.) based on your desired storage format, or mount an `rclone.conf` file.*

## Usage Guide

The container is designed to run once, execute the export and upload, and then exit. It is perfect for scheduling via cron or a scheduler like [Ofelia](https://github.com/mcuadros/ofelia).

### What a run does

1. Validates the configuration (`BW_*` variables, `RCLONE_DEST`, `CLEANUP_MIN_AGE` format) before anything touches the network.
2. Logs in with the API key, unlocks the vault and exports it to `/tmp` with mode `0600`.
3. Parses the export and, in archive mode, creates the `.7z` and verifies it with `7z t`.
4. Uploads the file with `rclone copy`.
5. Deletes backups older than `CLEANUP_MIN_AGE` — both formats, never the file written by this run.

**Exit codes:** `0` means the backup is in the destination; a failed retention step only prints a warning, and a destination that cannot delete does not turn a good backup into a failed run. `1` means no backup was uploaded (validation, login, unlock, export or upload failed).

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
docker run --rm \
   -e BW_HOST=https://vault.example.com \
   -e BW_CLIENTID=user.xxxxxxxx \
   -e BW_CLIENTSECRET=your_client_secret \
   -e BW_PASSWORD=YourMasterPassword \
   -e RCLONE_CONFIG_MYSMB_TYPE=smb \
   -e RCLONE_CONFIG_MYSMB_HOST=192.168.1.100 \
   -e RCLONE_CONFIG_MYSMB_USER=myuser \
   -e RCLONE_CONFIG_MYSMB_PASS="$(rclone obscure 'yourpassword')" \
   -e RCLONE_DEST=mysmb:backup_folder \
   benjaminaicheler/vaultwarden-export-rclone:latest
```

### Encryption and Archiving

If you wish to securely compress and password-protect your Vaultwarden export before uploading it, you can provide the `ARCHIVE_PASSWORD` environment variable.

```bash
# add the BW_* and RCLONE_CONFIG_* variables of your setup as well
docker run --rm \
   -e ARCHIVE_PASSWORD="your-strong-archive-password" \
   benjaminaicheler/vaultwarden-export-rclone:latest
```

When this variable is provided, the script uses `7zip` to create an AES-256 encrypted `.7z` archive containing the vault export instead of uploading plain `.json` files.

**Restoring from an encrypted archive:**
You can use standard unarchiving tools like `7z` to extract the JSON locally:
```bash
7z x -p"your-strong-archive-password" vault-export-YYYY-MM-DD_HHMMSS.7z
```

*Note: Bitwarden's JSON export contains your items, folders and collections, but **not** file attachments. Back those up separately if you rely on them.*

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

> `SMB_PATH` is deprecated. It is turned into the rclone connection string `:smb:<path>`, which reads the backend from the `RCLONE_SMB_*` environment variables — so this variant needs `RCLONE_SMB_HOST`, `RCLONE_SMB_USER` and `RCLONE_SMB_PASS` instead of the `RCLONE_CONFIG_<REMOTE>_*` variables used in section 1. New setups should use `RCLONE_DEST`.

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
- `ARCHIVE_PASSWORD` is passed to `7z` as a command-line argument, so it is visible in `/proc/<pid>/cmdline` inside the container for as long as the archive is being written. 7-Zip provides no other way to supply a password, so this is documented rather than worked around: keep the container's process namespace private and run it on a host you trust.
- The export is written to `/tmp` inside the container with mode `0600` (`umask 077`). Removing it after archiving is a normal `rm`, not a secure erase — blocks can survive in the container's copy-on-write layer.
- Always ensure your `.env` files or `docker-compose.yml` configs are strictly secured (e.g., `chmod 600`) and owned by `root`/your admin user only.
- The container runs as the unprivileged user `app` (uid/gid `10001`, `HOME=/home/app`). The Bitwarden CLI needs that home for its configuration; if you bind-mount a directory instead of using an rclone backend, it must be writable for uid `10001`.
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
