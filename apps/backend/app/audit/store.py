"""Audit stub — Oracle when configured, else in-memory list (MVP)."""
from collections import deque
from datetime import datetime, timezone

_buffer = deque(maxlen=1000)


def log_audit(actor: str, action: str, target: str, detail: str = ""):
    entry = {"ts": datetime.now(timezone.utc).isoformat(), "actor": actor, "action": action, "target": target, "detail": detail}
    _buffer.append(entry)
    return entry


def list_audit(limit: int = 50):
    return list(reversed(list(_buffer)))[ : limit]
