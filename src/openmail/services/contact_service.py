"""Contact CRUD service."""
from __future__ import annotations

from flask import jsonify

from openmail.db import get_db
from openmail.auth.current_user import current_user_id


def list_contacts(q: str = "") -> list[dict]:
    user_id = current_user_id()
    conn = get_db()
    if q:
        rows = conn.execute(
            """SELECT id, name, email, notes FROM contacts
            WHERE user_id = ? AND (LOWER(name) LIKE ? OR LOWER(email) LIKE ?)
            ORDER BY name LIMIT 20""",
            (user_id, f"%{q}%", f"%{q}%")
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT id, name, email, notes FROM contacts WHERE user_id = ? ORDER BY name",
            (user_id,)
        ).fetchall()
    return [dict(r) for r in rows]


def create_contact(name: str, email: str, notes: str | None) -> tuple[dict, int]:
    user_id = current_user_id()
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO contacts (user_id, name, email, notes) VALUES (?, ?, ?, ?)",
            (user_id, name, email, notes)
        )
        conn.commit()
        contact_id = cur.lastrowid
    except Exception:
        conn.rollback()
        return {"error": "Contact with this email already exists"}, 400
    return {"id": contact_id, "name": name, "email": email, "notes": notes}, 201


def update_contact(contact_id: int, fields: dict) -> dict | None:
    user_id = current_user_id()
    allowed = {'name', 'email', 'notes'}
    updates = {k: v for k, v in fields.items() if k in allowed}
    if not updates:
        return None
    conn = get_db()
    set_clause = ", ".join(f"{k} = ?" for k in updates)
    values = list(updates.values()) + [contact_id, user_id]
    conn.execute(
        f"UPDATE contacts SET {set_clause} WHERE id = ? AND user_id = ?",
        values
    )
    conn.commit()
    row = conn.execute(
        "SELECT id, name, email, notes FROM contacts WHERE id = ?",
        (contact_id,)
    ).fetchone()
    return dict(row) if row else None


def delete_contact(contact_id: int) -> bool:
    user_id = current_user_id()
    conn = get_db()
    cur = conn.execute(
        "DELETE FROM contacts WHERE id = ? AND user_id = ?",
        (contact_id, user_id)
    )
    conn.commit()
    return cur.rowcount > 0


# ---- Starred addresses ----

def add_starred_address(email: str) -> tuple[dict, int]:
    user_id = current_user_id()
    conn = get_db()
    existing = conn.execute(
        "SELECT 1 FROM starred_addresses WHERE user_id = ? AND email = ?",
        (user_id, email.lower())
    ).fetchone()
    if existing:
        return {"status": "exists"}, 200
    conn.execute(
        "INSERT OR IGNORE INTO starred_addresses (user_id, email) VALUES (?, ?)",
        (user_id, email.lower())
    )
    conn.commit()
    return {"status": "added"}, 201


def remove_starred_address(email: str) -> tuple[dict, int]:
    user_id = current_user_id()
    conn = get_db()
    conn.execute(
        "DELETE FROM starred_addresses WHERE user_id = ? AND email = ?",
        (user_id, email.lower())
    )
    conn.commit()
    return {"status": "removed"}, 200


def list_starred_addresses() -> list[str]:
    user_id = current_user_id()
    conn = get_db()
    rows = conn.execute(
        "SELECT email FROM starred_addresses WHERE user_id = ? ORDER BY email",
        (user_id,)
    ).fetchall()
    return [r['email'] for r in rows]


def is_starred_address(user_id: int, email: str) -> bool:
    conn = get_db()
    row = conn.execute(
        "SELECT 1 FROM starred_addresses WHERE user_id = ? AND email = ?",
        (user_id, (email or '').lower())
    ).fetchone()
    return row is not None


def contact_exists(email: str) -> bool:
    user_id = current_user_id()
    conn = get_db()
    row = conn.execute(
        "SELECT 1 FROM contacts WHERE user_id = ? AND LOWER(email) = LOWER(?)",
        (user_id, email)
    ).fetchone()
    return row is not None
