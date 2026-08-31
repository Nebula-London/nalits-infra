#!/bin/bash
set -e

# Clean stale state from previous runs
rm -f /var/run/sssd.pid
rm -f /var/lib/sss/pipes/nss
rm -f /var/lib/sss/pipes/pam
rm -f /var/lib/sss/pipes/private/sbus-*
rm -f /var/lib/sss/db/*.ldb
rm -f /var/lib/sss/mc/*

# Ensure directories exist with correct permissions
mkdir -p /var/lib/sss/pipes/private /var/lib/sss/db /var/lib/sss/mc /run/sshd
chown root:root /var/lib/sss
chmod 755 /var/lib/sss

echo "Starting SSSD..."
sssd -i --logger=files &
SSSD_PID=$!

# Wait for SSSD sockets to appear
echo "Waiting for SSSD sockets..."
for i in $(seq 1 30); do
    if [ -S /var/lib/sss/pipes/nss ] && [ -S /var/lib/sss/pipes/pam ]; then
        echo "SSSD sockets ready."
        SSSD_READY=1
        break
    fi
    if ! kill -0 $SSSD_PID 2>/dev/null; then
        echo "ERROR: SSSD process died."
        exit 1
    fi
    sleep 1
done

if [ "${SSSD_READY:-0}" != "1" ]; then
    echo "ERROR: SSSD failed to start within 30 seconds."
    exit 1
fi

echo "Testing AD user resolution..."
getent passwd Administrator || echo "Warning: Could not resolve Administrator yet"

echo "Generating SSH host keys..."
ssh-keygen -A

echo "Starting SSH server..."
exec /usr/sbin/sshd -D
