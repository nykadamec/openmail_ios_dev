"""Custom folder service."""
from __future__ import annotations

from openmail.db import get_db
from openmail.auth.current_user import current_user_id


def list_folders() -> dict:
    user_id = current_user_id()
    conn = get_db()
    custom = conn.execute(
        "SELECT id, name, color, icon FROM custom_folders WHERE user_id = ? ORDER BY name",
        (user_id,)
    ).fetchall()
    return {
        "system": ["inbox", "sent", "starred", "archive", "spam", "trash"],
        "custom": [dict(r) for r in custom]
    }


def create_folder(name: str, color: str, icon: str) -> tuple[dict, int]:
    user_id = current_user_id()
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO custom_folders (user_id, name, color, icon) VALUES (?, ?, ?, ?)",
            (user_id, name, color, icon)
        )
        conn.commit()
        folder_id = cur.lastrowid
    except Exception:
        conn.rollback()
        return {"error": "Folder already exists"}, 400
    return {"id": folder_id, "name": name, "color": color, "icon": icon}, 201


def delete_folder(folder_id: int) -> bool:
    user_id = current_user_id()
    conn = get_db()
    conn.execute(
        "DELETE FROM custom_folders WHERE id = ? AND user_id = ?",
        (folder_id, user_id)
    )
    # Move emails in this folder back to inbox
    conn.execute(
        "UPDATE emails SET custom_folder_id = NULL, folder = 'inbox' WHERE custom_folder_id = ? AND user_id = ?",
        (folder_id, user_id)
    )
    conn.commit()
    return True
