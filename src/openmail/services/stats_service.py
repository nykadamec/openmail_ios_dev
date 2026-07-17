"""Mailbox statistics service."""
from __future__ import annotations

from openmail.db import get_db
from openmail.auth.current_user import current_user_id


def get_stats() -> dict:
    user_id = current_user_id()
    conn = get_db()
    inbound = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND direction = 'inbound' AND is_trash = 0",
        (user_id,)
    ).fetchone()[0]
    outbound = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND direction = 'outbound' AND is_trash = 0",
        (user_id,)
    ).fetchone()[0]
    starred = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND is_starred = 1 AND is_trash = 0",
        (user_id,)
    ).fetchone()[0]
    unread = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND direction = 'inbound' AND is_read = 0 AND is_trash = 0",
        (user_id,)
    ).fetchone()[0]
    spam = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND is_spam = 1 AND is_trash = 0",
        (user_id,)
    ).fetchone()[0]
    trash = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE user_id = ? AND is_trash = 1",
        (user_id,)
    ).fetchone()[0]
    return {
        "inbound": inbound,
        "outbound": outbound,
        "starred": starred,
        "unread": unread,
        "spam": spam,
        "trash": trash,
    }
