# ===========================================
# Samba AD Domain Controller - arm64
# Custom build with AD DC support
# ===========================================

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Samba AD DC and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    samba \
    samba-ad-provision \
    samba-dsdb-modules \
    samba-vfs-modules \
    winbind \
    libnss-winbind \
    libpam-winbind \
    krb5-user \
    krb5-config \
    ldap-utils \
    smbclient \
    net-tools \
    iputils-ping \
    dnsutils \
    vim \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /var/lib/samba /etc/samba /var/log/samba /scripts

# Copy scripts
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Expose ports
EXPOSE 53/tcp 53/udp 88/tcp 88/udp 135/tcp 137/udp 138/udp 139/tcp 389/tcp 389/udp 445/tcp 636/tcp 3268/tcp 3269/tcp

# Health check
HEALTHCHECK --interval=60s --timeout=30s --start-period=120s --retries=3 \
    CMD /scripts/healthcheck.sh || exit 1

# Entry point
ENTRYPOINT ["/scripts/init-ad.sh"]