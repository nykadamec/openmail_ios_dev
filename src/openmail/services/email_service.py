"""Email CRUD and listing service."""
from __future__ import annotations

import json
from typing import Any

from openmail.db import get_db
from openmail.crypto.dek import decrypt_email_field
from openmail.auth.current_user import current_user_id


def _decrypt_email_dict(row: dict, user_id: int) -> dict:
    d = dict(row)
    for field in ('sender_name', 'sender_email', 'recipient', 'subject', 'preview', 'body_text', 'body_html'):
        if field in d:
            d[field] = decrypt_email_field(d[field], user_id)
    return d


def list_emails(
    folder: str = 'inbox',
    direction: str = 'inbound',
    starred: int | None = None,
    is_spam: int | None = None,
    is_trash: int | None = None,
    custom_folder_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    user_id = current_user_id()
    conn = get_db()
    params: list[Any] = [user_id]
    where = ['user_id = ?']

    where.append('direction = ?')
    params.append(direction)

    if folder and not custom_folder_id:
        where.append('folder = ?')
        params.append(folder)
    if starred is not None:
        where.append('is_starred = ?')
        params.append(starred)
    if is_spam is not None:
        where.append('is_spam = ?')
        params.append(is_spam)
    if is_trash is not None:
        where.append('is_trash = ?')
        params.append(is_trash)
    if custom_folder_id:
        where.append('custom_folder_id = ?')
        params.append(custom_folder_id)

    where_sql = ' AND '.join(where)
    count_sql = f"SELECT COUNT(*) FROM emails WHERE {where_sql}"
    total = conn.execute(count_sql, params).fetchone()[0]

    select_sql = (
        "SELECT id, folder, custom_folder_id, sender_name, sender_email, recipient, subject, preview, "
        "is_starred, is_read, is_spam, is_trash, created_at, received_at FROM emails WHERE "
        f"{where_sql} ORDER BY COALESCE(received_at, created_at) DESC LIMIT ? OFFSET ?"
    )
    rows = conn.execute(select_sql, params + [limit, offset]).fetchall()

    result = [_decrypt_email_dict(dict(row), user_id) for row in rows]
    return {"emails": result, "total": total, "limit": limit, "offset": offset}


def get_email(email_id: int) -> dict | None:
    user_id = current_user_id()
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM emails WHERE id = ? AND user_id = ?",
        (email_id, user_id)
    ).fetchone()
    if row:
        conn.execute(
            "UPDATE emails SET is_read = 1 WHERE id = ? AND user_id = ?",
            (email_id, user_id)
        )
        conn.commit()
    if row is None:
        return None
    d = _decrypt_email_dict(dict(row), user_id)
    try:
        d['attachments'] = json.loads(d.get('attachments') or '[]')
    except (json.JSONDecodeError, TypeError):
        d['attachments'] = []
    return d


def update_email(email_id: int, fields: dict) -> dict | None:
    user_id = current_user_id()
    allowed = {"is_starred", "is_read", "folder", "is_spam", "is_trash", "custom_folder_id"}
    updates = {k: v for k, v in fields.items() if k in allowed}
    if not updates:
        return None
    conn = get_db()
    set_clause = ", ".join(f"{k} = ?" for k in updates)
    values = list(updates.values()) + [email_id, user_id]
    conn.execute(
        f"UPDATE emails SET {set_clause} WHERE id = ? AND user_id = ?",
        values
    )
    conn.commit()
    row = conn.execute(
        "SELECT * FROM emails WHERE id = ? AND user_id = ?",
        (email_id, user_id)
    ).fetchone()
    return _decrypt_email_dict(dict(row), user_id) if row else None


def move_to_trash(email_id: int) -> bool:
    user_id = current_user_id()
    conn = get_db()
    cur = conn.execute(
        "UPDATE emails SET is_trash = 1 WHERE id = ? AND user_id = ?",
        (email_id, user_id)
    )
    conn.commit()
    return cur.rowcount > 0


def bulk_action(ids: list[int], action: str) -> int:
    user_id = current_user_id()
    if not ids or not action:
        return 0
    conn = get_db()
    placeholders = ",".join("?" for _ in ids)
    params = list(ids) + [user_id]
    if action == "read":
        sql = f"UPDATE emails SET is_read = 1 WHERE id IN ({placeholders}) AND user_id = ?"
    elif action == "unread":
        sql = f"UPDATE emails SET is_read = 0 WHERE id IN ({placeholders}) AND user_id = ?"
    elif action == "trash":
        sql = f"UPDATE emails SET is_trash = 1 WHERE id IN ({placeholders}) AND user_id = ?"
    elif action == "spam":
        sql = f"UPDATE emails SET is_spam = 1, folder = 'spam' WHERE id IN ({placeholders}) AND user_id = ?"
    elif action == "delete":
        # Hard delete: also remove attachment files.
        rows = conn.execute(
            f"SELECT id FROM emails WHERE id IN ({placeholders}) AND user_id = ?",
            params
        ).fetchall()
        ids_to_delete = [r['id'] for r in rows]
        if ids_to_delete:
            _delete_attachment_files(ids_to_delete)
        ph2 = ",".join("?" for _ in ids_to_delete)
        sql = f"DELETE FROM emails WHERE id IN ({ph2}) AND user_id = ?"
        params = ids_to_delete + [user_id]
    else:
        return 0
    cur = conn.execute(sql, params)
    conn.commit()
    return cur.rowcount


def _delete_attachment_files(email_ids: list[int]) -> None:
    from openmail.config import ATTACHMENTS_DIR
    for email_id in email_ids:
        att_dir = ATTACHMENTS_DIR / str(email_id)
        if att_dir.exists():
            import shutil
            shutil.rmtree(att_dir, ignore_errors=True)
