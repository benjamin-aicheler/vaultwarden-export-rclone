FROM node:25-alpine

# Copy the pre-compiled rclone binary directly from the official rclone image
COPY --from=rclone/rclone:latest /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=rclone/rclone:latest /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Install Bitwarden CLI
RUN npm install -g @bitwarden/cli@latest && \
    npm cache clean --force

# Setup execution script
COPY export-and-upload.sh /usr/local/bin/export-and-upload.sh
RUN chmod +x /usr/local/bin/export-and-upload.sh

ENTRYPOINT ["/usr/local/bin/export-and-upload.sh"]