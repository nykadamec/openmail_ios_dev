"""Email CRUD and listing service."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from openmail.db import get_db
from openmail.crypto.dek import decrypt_email_field
from openmail.auth.current_user import current_user_id


def get_attachment(email_id: int, filename: str) -> dict | None:
    """Return a verified attachment for the current user.

    The file name must be present in the email's persisted attachment metadata;
    the email lookup is also scoped to the authenticated user.  Returning the
    resolved path only after both checks keeps the attachment route from being
    used to probe another user's mail or arbitrary files on disk.
    """
    user_id = current_user_id()
    conn = get_db()
    row = conn.execute(
        "SELECT attachments FROM emails WHERE id = ? AND user_id = ?",
        (email_id, user_id),
    ).fetchone()
    if row is None:
        return None

    try:
        attachments = json.loads(row['attachments'] or '[]')
    except (json.JSONDecodeError, TypeError):
        return None
    if not isinstance(attachments, list):
        return None

    metadata = next(
        (item for item in attachments
         if isinstance(item, dict) and item.get('filename') == filename),
        None,
    )
    if metadata is None:
        return None

    # Reject absolute paths and traversal before resolving the candidate.
    requested = Path(filename)
    if requested.is_absolute() or '..' in requested.parts:
        return None

    from openmail.config import ATTACHMENTS_DIR
    attachment_dir = (ATTACHMENTS_DIR / str(email_id)).resolve()
    file_path = (attachment_dir / requested).resolve()
    try:
        file_path.relative_to(attachment_dir)
    except ValueError:
        return None
    if not file_path.is_file():
        return None

    content_type = metadata.get('content_type')
    if not isinstance(content_type, str) or not content_type:
        content_type = 'application/octet-stream'
    return {
        'path': file_path,
        'filename': filename,
        'content_type': content_type,
    }


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
    q: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> dict:
    user_id = current_user_id()
    conn = get_db()
    params: list[Any] = [user_id]
    where = ['user_id = ?']

    # Search must be performed after decryption: email fields are encrypted at
    # rest and therefore cannot be searched with SQL LIKE.  In search mode the
    # folder filters are deliberately omitted so Spam and Trash are included.
    global_search = q is not None

    if not global_search:
        where.append('direction = ?')
        params.append(direction)

    if folder and not custom_folder_id and not global_search:
        where.append('folder = ?')
        params.append(folder)
    if starred is not None and not global_search:
        where.append('is_starred = ?')
        params.append(starred)
    if is_spam is not None and not global_search:
        where.append('is_spam = ?')
        params.append(is_spam)
    if is_trash is not None and not global_search:
        where.append('is_trash = ?')
        params.append(is_trash)
    if custom_folder_id and not global_search:
        where.append('custom_folder_id = ?')
        params.append(custom_folder_id)

    where_sql = ' AND '.join(where)
    if global_search:
        # Fetch in the same order as the ordinary listing, then filter the
        # decrypted values and paginate the matching rows.  Searching body_text
        # and body_html is intentional even though those fields are not part of
        # the listing response.
        select_sql = (
            "SELECT id, folder, custom_folder_id, sender_name, sender_email, recipient, subject, preview, "
            "body_text, body_html, is_starred, is_read, is_spam, is_trash, created_at, received_at "
            "FROM emails WHERE "
            f"{where_sql} ORDER BY COALESCE(received_at, created_at) DESC"
        )
        rows = conn.execute(select_sql, params).fetchall()
        term = q.casefold()
        matching_rows = []
        for row in rows:
            decrypted = _decrypt_email_dict(dict(row), user_id)
            searchable = (
                decrypted.get('sender_name'), decrypted.get('sender_email'),
                decrypted.get('recipient'), decrypted.get('subject'),
                decrypted.get('preview'), decrypted.get('body_text'),
                decrypted.get('body_html'),
            )
            if any(term in value.casefold() for value in searchable if isinstance(value, str)):
                matching_rows.append(decrypted)
        total = len(matching_rows)
        result = matching_rows[offset:offset + limit]
    else:
        count_sql = f"SELECT COUNT(*) FROM emails WHERE {where_sql}"
        total = conn.execute(count_sql, params).fetchone()[0]

        select_sql = (
            "SELECT id, folder, custom_folder_id, sender_name, sender_email, recipient, subject, preview, "
            "is_starred, is_read, is_spam, is_trash, created_at, received_at FROM emails WHERE "
            f"{where_sql} ORDER BY COALESCE(received_at, created_at) DESC LIMIT ? OFFSET ?"
        )
        rows = conn.execute(select_sql, params + [limit, offset]).fetchall()
        result = [_decrypt_email_dict(dict(row), user_id) for row in rows]

    # Body fields are only loaded for searching and must not become part of the
    # existing list response contract.
    for email in result:
        email.pop('body_text', None)
        email.pop('body_html', None)
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
