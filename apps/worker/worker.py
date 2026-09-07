"""Samba AD worker — Redis queue stub. MVP: periodic LDAP stats + audit cleanup loop.

Future: replace with Oracle-only scheduler if Redis removed.
"""
import time
import os
import redis
from loguru import logger

REDIS_URL = os.getenv("REDIS_URL", "redis://samba-redis:6379/0")
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")

def main():
    logger.info(f"Worker starting — redis {REDIS_URL}")
    while True:
        try:
            r = redis.from_url(REDIS_URL, password=REDIS_PASSWORD or None, socket_connect_timeout=3)
            r.ping()
            logger.info("Worker: redis OK, queue idle (MVP stub)")
        except Exception as e:
            logger.warning(f"Worker: redis not ready: {e}")
        # placeholder jobs: LDAP sync cache, expiring passwords, audit cleanup
        time.sleep(30)

if __name__ == "__main__":
    main()
