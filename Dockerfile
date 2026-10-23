# Pinned base images: the rclone stage exists so the image reference is a real
# FROM line (Dependabot tracks those reliably, not `COPY --from=image:tag`).
FROM rclone/rclone:1.75.2 AS rclone

FROM node:26.12-alpine

# Copy the pre-compiled rclone binary and the CA bundle from the rclone image
COPY --from=rclone /usr/local/bin/rclone /usr/local/bin/rclone
COPY --from=rclone /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Install Bitwarden CLI and 7zip
RUN apk add --no-cache 7zip && \
    npm install -g @bitwarden/cli@2026.10.0 && \
    npm cache clean --force

# Setup execution script
COPY export-and-upload.sh /usr/local/bin/export-and-upload.sh
RUN chmod +x /usr/local/bin/export-and-upload.sh

# Run unprivileged. The Bitwarden CLI keeps its session under $HOME/.config, so
# the user needs its own writable home; the fixed uid makes bind mounts predictable.
RUN addgroup -g 10001 app && \
    adduser -S -u 10001 -G app -h /home/app app
ENV HOME=/home/app
USER app

ENTRYPOINT ["/usr/local/bin/export-and-upload.sh"]