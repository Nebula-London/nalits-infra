# ===========================================
# LAM (LDAP Account Manager) Docker Image
# Based on official LAM image with custom config
# ===========================================

FROM ldapaccountmanager/lam:latest

# Switch to root for configuration
USER root

# Install additional tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ldap-utils \
    vim \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy custom config template
COPY config/lam.conf /var/lib/ldap-account-manager/config/lam.conf.template

# Create log directory
RUN mkdir -p /var/log/lam && chown www-data:www-data /var/log/lam

# Switch back to www-data
USER www-data

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:80/ || exit 1

# Expose port
EXPOSE 80

# Entry point
ENTRYPOINT ["/entrypoint.sh"]