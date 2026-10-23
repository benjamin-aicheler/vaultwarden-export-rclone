# Pinned base images: the rclone stage exists so the image reference is a real
# FROM line (Dependabot tracks those reliably, not `COPY --from=image:tag`).
FROM rclone/rclone:1.75.2 AS rclone

FROM node:26.12-alpine

# Copy the pre-compiled rclone binary and the CA bundle from the rclone image
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=rclone /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Install Bitwarden CLI and 7zip
RUN apk add --no-cache 7zip && \
    npm install -g @bitwarden/cli@2026.9.1 && \
    npm cache clean --force

# Setup execution script
COPY export-and-upload.sh /usr/local/bin/export-and-upload.sh
RUN chmod +x /usr/local/bin/export-and-upload.sh

ENTRYPOINT ["/usr/local/bin/export-and-upload.sh"]