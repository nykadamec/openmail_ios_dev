"""Contact CRUD service."""
from __future__ import annotations

from openmail.db import get_db
from openmail.auth.current_user import current_user_id


def _normalize_email(email: str) -> str:
    return (email or '').strip().lower()


def _normalize_domain(domain: str) -> str:
    return (domain or '').strip().lower().lstrip('@').rstrip('.')


def list_contacts(q: str = "") -> list[dict]:
    user_id = current_user_id()
    conn = get_db()
    if q:
        rows = conn.execute(
            """SELECT id, name, email, notes, is_starred FROM contacts
            WHERE user_id = ? AND (LOWER(name) LIKE ? OR LOWER(email) LIKE ?)
            ORDER BY name LIMIT 20""",
            (user_id, f"%{q}%", f"%{q}%")
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT id, name, email, notes, is_starred FROM contacts WHERE user_id = ? ORDER BY name",
            (user_id,)
        ).fetchall()
    return [dict(r) for r in rows]


def create_contact(name: str, email: str, notes: str | None) -> tuple[dict, int]:
    user_id = current_user_id()
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO contacts (user_id, name, email, notes) VALUES (?, ?, ?, ?)",
            (user_id, name, _normalize_email(email), notes)
        )
        conn.commit()
        contact_id = cur.lastrowid
    except Exception:
        conn.rollback()
        return {"error": "Contact with this email already exists"}, 400
    return {"id": contact_id, "name": name, "email": _normalize_email(email), "notes": notes, "is_starred": 0}, 201


def update_contact(contact_id: int, fields: dict) -> dict | None:
    user_id = current_user_id()
    allowed = {'name', 'email', 'notes', 'is_starred'}
    updates = {k: v for k, v in fields.items() if k in allowed}
    if 'email' in updates:
        updates['email'] = _normalize_email(updates['email'])
    if 'is_starred' in updates:
        updates['is_starred'] = 1 if updates['is_starred'] else 0
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
        "SELECT id, name, email, notes, is_starred FROM contacts WHERE id = ? AND user_id = ?",
        (contact_id, user_id)
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
    email = _normalize_email(email)
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
        (user_id, _normalize_email(email))
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
        (user_id, _normalize_email(email))
    ).fetchone()
    if row:
        return True
    row = conn.execute(
        "SELECT 1 FROM contacts WHERE user_id = ? AND email = ? AND is_starred = 1",
        (user_id, _normalize_email(email)),
    ).fetchone()
    return row is not None


def list_domain_rules() -> list[dict]:
    user_id = current_user_id()
    rows = get_db().execute(
        "SELECT id, domain, action, enabled FROM domain_rules WHERE user_id = ? ORDER BY domain",
        (user_id,),
    ).fetchall()
    return [dict(row) for row in rows]


def create_domain_rule(domain: str, action: str = 'star', enabled: bool = True) -> tuple[dict, int]:
    user_id = current_user_id()
    domain = _normalize_domain(domain)
    if not domain or action != 'star':
        return {"error": "Valid domain and action required"}, 400
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO domain_rules (user_id, domain, action, enabled) VALUES (?, ?, ?, ?)",
            (user_id, domain, action, 1 if enabled else 0),
        )
        conn.commit()
    except Exception:
        conn.rollback()
        return {"error": "Domain rule already exists"}, 409
    return {"id": cur.lastrowid, "domain": domain, "action": action, "enabled": bool(enabled)}, 201


def update_domain_rule(rule_id: int, fields: dict) -> dict | None:
    user_id = current_user_id()
    updates = {}
    if 'domain' in fields:
        updates['domain'] = _normalize_domain(fields['domain'])
    if 'enabled' in fields:
        updates['enabled'] = 1 if bool(fields['enabled']) else 0
    if 'action' in fields and fields['action'] != 'star':
        return None
    if not updates:
        return None
    conn = get_db()
    values = list(updates.values()) + [rule_id, user_id]
    conn.execute("UPDATE domain_rules SET " + ", ".join(f"{k} = ?" for k in updates) + ", updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?", values)
    conn.commit()
    row = conn.execute("SELECT id, domain, action, enabled FROM domain_rules WHERE id = ? AND user_id = ?", (rule_id, user_id)).fetchone()
    if not row:
        return None
    result = dict(row)
    result['enabled'] = bool(result['enabled'])
    return result


def delete_domain_rule(rule_id: int) -> bool:
    conn = get_db()
    cur = conn.execute("DELETE FROM domain_rules WHERE id = ? AND user_id = ?", (rule_id, current_user_id()))
    conn.commit()
    return cur.rowcount > 0


def is_domain_rule_enabled(user_id: int, email: str) -> bool:
    domain = _normalize_email(email).rsplit('@', 1)[-1] if '@' in _normalize_email(email) else ''
    if not domain:
        return False
    row = get_db().execute(
        "SELECT 1 FROM domain_rules WHERE user_id = ? AND domain = ? AND action = 'star' AND enabled = 1",
        (user_id, domain),
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
