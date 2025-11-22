# Start from a glibc-based image (Debian)
FROM debian:bullseye-slim

# Set the versions to install
ENV BW_VERSION=2025.11.0
ARG RCLONE_VERSION=1.72.0

# 1. Install dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y \
    curl \
    unzip \
    jq \
    ca-certificates \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# 2. Install rclone (manually, to get a modern version)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -LfSso /tmp/rclone.zip "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${ARCH}.zip" && \
    unzip -o /tmp/rclone.zip -d /tmp/rclone-extracted && \
    cp /tmp/rclone-extracted/rclone-v*/rclone /usr/local/bin/ && \
    chown root:root /usr/local/bin/rclone && \
    chmod 755 /usr/local/bin/rclone && \
    rm -rf /tmp/rclone.zip /tmp/rclone-extracted

# 3. Install Bitwarden CLI
RUN ARCH=$(dpkg --print-architecture) && \
    case $ARCH in \
      amd64)   BW_FILENAME="bw-linux-${BW_VERSION}.zip" ;; \
      arm64)   echo "ERROR: Bitwarden does not provide a pre-compiled arm64 CLI binary for Linux." \
               && echo "This image can only be built on an amd64 host." \
               && exit 1 ;; \
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    curl -LfSso /tmp/bw-linux.zip "https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/${BW_FILENAME}" && \
    unzip -o /tmp/bw-linux.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/bw && \
    rm /tmp/bw-linux.zip

# 4. Add the execution script
COPY export-and-upload.sh /usr/local/bin/export-and-upload.sh
RUN chmod +x /usr/local/bin/export-and-upload.sh

# 5. Set the script as the entrypoint
ENTRYPOINT ["/usr/local/bin/export-and-upload.sh"]