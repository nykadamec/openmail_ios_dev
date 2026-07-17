"""Session creation, validation, deletion and cleanup."""
from __future__ import annotations

import secrets
from datetime import datetime, timezone, timedelta

from flask import request, g

from openmail.db import get_db
from openmail.config import SESSION_TIMEOUT_MINUTES


SESSION_TIMEOUT = timedelta(minutes=SESSION_TIMEOUT_MINUTES)


def cleanup_expired_sessions() -> int:
    """Delete all expired sessions. Returns number of deleted rows."""
    cutoff = (datetime.now(timezone.utc) - SESSION_TIMEOUT).isoformat()
    conn = get_db()
    cur = conn.execute("DELETE FROM sessions WHERE last_seen < ?", (cutoff,))
    conn.commit()
    return cur.rowcount


def create_session(user_id: int) -> str:
    cleanup_expired_sessions()
    sid = secrets.token_urlsafe(32)
    conn = get_db()
    conn.execute(
        "INSERT INTO sessions (id, user_id, last_seen) VALUES (?, ?, ?)",
        (sid, user_id, datetime.now(timezone.utc).isoformat())
    )
    conn.commit()
    return sid


def get_session(sid: str | None) -> dict | None:
    """Get session if not expired. Refresh last_seen on success."""
    if not sid:
        return None
    conn = get_db()
    row = conn.execute(
        "SELECT id, user_id, last_seen FROM sessions WHERE id = ?",
        (sid,)
    ).fetchone()
    if not row:
        return None
    last_seen = datetime.fromisoformat(row['last_seen'])
    if datetime.now(timezone.utc) - last_seen > SESSION_TIMEOUT:
        conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
        conn.commit()
        return None
    conn.execute(
        "UPDATE sessions SET last_seen = ? WHERE id = ?",
        (datetime.now(timezone.utc).isoformat(), sid)
    )
    conn.commit()
    return {'id': row['id'], 'user_id': row['user_id']}


def delete_session(sid: str | None) -> None:
    if not sid:
        return
    conn = get_db()
    conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
    conn.commit()


def current_session_id() -> str | None:
    return request.cookies.get('session_id')
