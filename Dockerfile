ARG DEBIAN_VERSION=bookworm
ARG RUNITOR_VERSION=$(curl -Ls -o /dev/null -w %{url_effective} "https://github.com/bdd/runitor/releases/latest" | cut -d '/' -f8)
ARG RUNITOR_ARCH=amd64

FROM debian:$DEBIAN_VERSION-slim
LABEL authors="DJArbz"

#==================================================
# SYSTEM Environment Variables
#==================================================
ENV DEBIAN_VERSION=$DEBIAN_VERSION
ENV PBC_LAST_RUN_FILE=/run/pbs-client.run

#==================================================
# PROXMOX Environment Variables
#==================================================
# The recommended solution for shielding hosts is using tunnels such as wireguard, instead of using an HTTP proxy.
# ENV ALL_PROXY=
# ENV PBS_FINGERPRINT=
# ENV PBS_REPOSITORY=backups
# ENV PBS_DATASTORE_NS=

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
# Install Dependancies
#==================================================
RUN apt-get update -yqq && \
    DEBIAN_FRONTEND=noninteractive \
      apt-get -yqq -o=Dpkg::Use-Pty=0 --no-install-recommends --no-install-suggests install \
      apt-transport-https \
      software-properties-common \
      ca-certificates \
      gpg \
      gnupg2 \
      curl \
      wget \
      jq && \
    apt-get clean

#==================================================
# Add Repository
#==================================================
RUN proxmox-release-${DEBIAN_VERSION}.gpg && \
    curl -fsSL "https://enterprise.proxmox.com/debian/proxmox-release-${DEBIAN_VERSION}.gpg" | \
    gpg --dearmor -o "/etc/apt/keyrings/proxmox-release-${DEBIAN_VERSION}.gpg" && \
    add-apt-repository "deb [signed-by=/etc/apt/keyrings/proxmox-release-${DEBIAN_VERSION}.gpg] http://download.proxmox.com/debian/pbs-client ${DEBIAN_VERSION} main"

#==================================================
# Install Proxmox Backup Client
#==================================================
RUN apt-get update -yqq && \
  DEBIAN_FRONTEND=noninteractive \
    apt-get -yqq -o=Dpkg::Use-Pty=0 --no-install-recommends --no-install-suggests install \
    proxmox-backup-client && \
  apt-get clean
VOLUME /root/.config/proxmox-backup/
ENV PBC_CONFIG_DIR=/root/.config/proxmox-backup/
ENV PBC_BACKUP_ROOT=/backup

#==================================================
# Install Runitor for Healthchecks.io
#==================================================
ENV RUNITOR_VERSION=$RUNITOR_VERSION
RUN curl -fsSL https://github.com/bdd/runitor/releases/download/${RUNITOR_VERSION}/runitor-${RUNITOR_VERSION}-linux-${RUNITOR_ARCH} -o /usr/local/bin/runitor && \
    chmod +x /usr/local/bin/runitor
ENV PBC_HEALTHCHECKS_API_RETRIES=5
ENV PBC_HEALTHCHECKS_API_TIMEOUT=10s

#==================================================
# Copy Scripts
#==================================================
COPY entrypoint.sh /
COPY scripts /scripts
RUN chmod a+x /entrypoint.sh /scripts/*

#==================================================
# Start!
#==================================================
STOPSIGNAL SIGINT
ENTRYPOINT ["/entrypoint.sh"]
