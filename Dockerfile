ARG DEBIAN_VERSION=trixie
FROM debian:$DEBIAN_VERSION-slim
LABEL authors="DJArbz"

#==================================================
# Redefine ARGs (FROM clears them)
#==================================================
# TARGETARCH is automatically populated by Buildx (e.g., amd64, arm64)
ARG TARGETARCH
# ARM64_URL is passed dynamically via our GitHub Action
ARG ARM64_URL

ARG DEBIAN_VERSION=trixie
ENV DEBIAN_VERSION=$DEBIAN_VERSION

# Set shell to bash with pipefail to catch errors in piped commands
SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

#==================================================
# PROXMOX Environment Variables
#==================================================
# The recommended solution for shielding hosts is using tunnels such as wireguard, instead of using an HTTP proxy.
# ENV ALL_PROXY=
# ENV PBS_FINGERPRINT=
# ENV PBS_REPOSITORY=backups
# ENV PBS_NAMESPACE=

# Proxmox User Password/Secret
# Passwords must be valid UTF-8 and may not contain newlines.
# For your convenience, Proxmox Backup Server only uses the first line as password, so you can add arbitrary comments after the first newline.
# The first defined environment variable in the order below is preferred.
# ENV PBS_PASSWORD=
# ENV PBS_PASSWORD_FD=
# ENV PBS_PASSWORD_FILE=
# ENV PBS_PASSWORD_CMD=

# Proxmox Encryption Password
# Passwords must be valid UTF-8 and may not contain newlines.
# For your convenience, Proxmox Backup Server only uses the first line as password, so you can add arbitrary comments after the first newline.
# The first defined environment variable in the order below is preferred.
# ENV PBS_ENCRYPTION_PASSWORD=
# ENV PBS_ENCRYPTION_PASSWORD_FD=
# ENV PBS_ENCRYPTION_PASSWORD_FILE=
# ENV PBS_ENCRYPTION_PASSWORD_CMD=

# Proxmox Command Output
ENV PROXMOX_OUTPUT_FORMAT=text
# ENV PROXMOX_OUTPUT_NO_BORDER=
# ENV PROXMOX_OUTPUT_NO_HEADER=

#==================================================
# Install Dependencies
#==================================================
# Hadolint(DL3008): [hadolint] warning: Pin versions in apt get install.
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  cron \
  gpg \
  gnupg2 \
  curl \
  wget \
  jq

apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

#==================================================
# Install Proxmox Backup Client
#==================================================
# Hadolint(DL3008): [hadolint] warning: Pin versions in apt get install.
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
if [ "$TARGETARCH" = "amd64" ]; then
  # Install officially supported amd64 package
  curl -fsSL "https://enterprise.proxmox.com/debian/proxmox-release-${DEBIAN_VERSION}.gpg" | \
    gpg --dearmor -o "/etc/apt/keyrings/proxmox-release-${DEBIAN_VERSION}.gpg" && \
  echo "deb [signed-by=/etc/apt/keyrings/proxmox-release-${DEBIAN_VERSION}.gpg] \
    http://download.proxmox.com/debian/pbs-client ${DEBIAN_VERSION} main" | \
    tee /etc/apt/sources.list.d/proxmox-backup-client.list

  apt-get update
  apt-get install -y --no-install-recommends proxmox-backup-client

elif [ "$TARGETARCH" = "arm64" ]; then
  # Download and install unofficial arm64 package using the injected ARG
  curl -fsSL -o /tmp/pbs-client-arm64.deb "${ARM64_URL}"
  apt-get install -y --no-install-recommends /tmp/pbs-client-arm64.deb
  rm /tmp/pbs-client-arm64.deb
fi

apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

VOLUME /root/.config/proxmox-backup/
ENV PBC_CONFIG_DIR=/root/.config/proxmox-backup/
ENV PBC_BACKUP_ROOT=/backup
ENV PBC_BACKUP_FINDMNT=true
ENV PBC_OPT_CHANGE_DETECTION_MODE=metadata

#==================================================
# Install Runitor for Healthchecks.io
#==================================================
COPY --chmod=755 --from=runitor/runitor:debian /usr/local/bin/runitor /usr/local/bin/runitor
ENV PBC_HEALTHCHECKS_API_RETRIES=5
ENV PBC_HEALTHCHECKS_API_TIMEOUT=10s

#==================================================
# Copy Scripts
#==================================================
COPY --chmod=755 entrypoint.sh /
COPY --chmod=755 scripts /scripts

#==================================================
# Start!
#==================================================
ENV PBC_LAST_RUN_FILE=/run/pbs-client.run
STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
