FROM certbot/certbot:latest

COPY renew.sh /renew.sh
COPY cron /etc/cron.d/certbot-renew

RUN chmod +x /renew.sh && \
    crontab /etc/cron.d/certbot-renew

ENTRYPOINT ["crond", "-f"]
