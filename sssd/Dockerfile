FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    sssd \
    sssd-ldap \
    sssd-krb5 \
    sssd-tools \
    libnss-sss \
    libpam-sss \
    libsss-sudo \
    libpam-mkhomedir \
    krb5-user \
    krb5-config \
    samba-common-bin \
    ldap-utils \
    dnsutils \
    iputils-ping \
    tini \
    openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/sss/pipes/private \
             /var/lib/sss/db \
             /var/lib/sss/mc \
             /var/log/sssd \
             /run/sshd \
             /home

RUN sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysCommand.*/AuthorizedKeysCommand \/usr\/bin\/sss_ssh_authorizedkeys/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysCommandUser.*/AuthorizedKeysCommandUser nobody/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

COPY config/sssd.conf /etc/sssd/sssd.conf
COPY config/krb5.conf /etc/krb5.conf
COPY config/nsswitch.conf /etc/nsswitch.conf
COPY pam.d/ /etc/pam.d/
COPY config/sudoers.d/ /etc/sudoers.d/

RUN chmod 600 /etc/sssd/sssd.conf && \
    chmod 644 /etc/krb5.conf /etc/nsswitch.conf && \
    chmod 440 /etc/sudoers.d/root-sssd && \
    chown -R root:root /var/lib/sss /var/log/sssd /run/sshd

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
