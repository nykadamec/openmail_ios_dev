"""User creation and password verification."""
from __future__ import annotations

import base64
import secrets
from typing import Optional

import bcrypt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from openmail.db import get_db
from openmail.crypto.dek import (
    encrypt_dek,
    decrypt_dek_with_fallback,
    set_user_dek,
    clear_user_dek,
)
from openmail.config import PBKDF2_ITERATIONS


def has_users() -> bool:
    conn = get_db()
    row = conn.execute("SELECT COUNT(*) as c FROM users").fetchone()
    return row['c'] > 0


def create_user(username: str, password: str, email: str | None = None, from_name: str | None = None) -> int:
    """Create a new user, generate a DEK encrypted by password, and cache the DEK."""
    pw_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    dek = AESGCM.generate_key(bit_length=256)
    salt = secrets.token_bytes(16)
    encrypted_dek = encrypt_dek(dek, password, salt)
    conn = get_db()
    cur = conn.execute(
        "INSERT INTO users (username, password_hash, dek_salt, encrypted_dek, email, from_name) VALUES (?, ?, ?, ?, ?, ?)",
        (username, pw_hash, base64.urlsafe_b64encode(salt).decode(), encrypted_dek, email, from_name)
    )
    conn.commit()
    user_id = cur.lastrowid
    assert user_id is not None
    set_user_dek(user_id, dek)
    return user_id


def get_user_by_id(user_id: int) -> dict | None:
    """Return user dict by id, or None."""
    conn = get_db()
    row = conn.execute(
        "SELECT id, username, email, from_name, first_name, last_name, phone FROM users WHERE id = ?",
        (user_id,)
    ).fetchone()
    return dict(row) if row else None


def get_user_by_email(email: str) -> dict | None:
    """Return user dict by email address, or None."""
    conn = get_db()
    row = conn.execute(
        "SELECT id, username, email, from_name, first_name, last_name, phone FROM users WHERE LOWER(email) = LOWER(?)",
        (email,)
    ).fetchone()
    return dict(row) if row else None


def update_user_profile(
    user_id: int,
    first_name: str | None = None,
    last_name: str | None = None,
    phone: str | None = None,
) -> dict | None:
    """Update profile fields. None = keep existing, empty string = NULL.

    Trims values, validates lengths (names max 100, phone max 32).
    Raises ValueError on validation failure. Returns updated user dict.
    """
    _KEEP: object = object()

    def _normalize(value: str | None, max_len: int, field: str) -> str | None | object:
        if value is None:
            return _KEEP
        v = value.strip() if isinstance(value, str) else value
        if not v:
            return None
        if len(v) > max_len:
            raise ValueError(f"{field} too long (max {max_len} chars)")
        return v

    new_first = _normalize(first_name, 100, "first_name")
    new_last = _normalize(last_name, 100, "last_name")
    new_phone = _normalize(phone, 32, "phone")

    conn = get_db()
    row = conn.execute(
        "SELECT first_name, last_name, phone FROM users WHERE id = ?",
        (user_id,)
    ).fetchone()
    if not row:
        return None
    final_first = row['first_name'] if new_first is _KEEP else new_first
    final_last = row['last_name'] if new_last is _KEEP else new_last
    final_phone = row['phone'] if new_phone is _KEEP else new_phone
    conn.execute(
        "UPDATE users SET first_name = ?, last_name = ?, phone = ? WHERE id = ?",
        (final_first, final_last, final_phone, user_id)
    )
    conn.commit()
    return get_user_by_id(user_id)


def get_user_from_address(user_id: int) -> tuple[str, str]:
    """Return (email, from_name) for a user, falling back to global config."""
    from openmail.config import FROM_EMAIL, FROM_NAME
    user = get_user_by_id(user_id)
    email = (user.get('email') or FROM_EMAIL) if user else FROM_EMAIL
    if user:
        first = (user.get('first_name') or '').strip()
        last = (user.get('last_name') or '').strip()
        if first or last:
            composed = f"{first} {last}".strip() if (first and last) else (first or last)
            return email, composed
        name = user.get('from_name') or FROM_NAME
    else:
        name = FROM_NAME
    return email, name


def verify_user(username: str, password: str) -> Optional[int]:
    """Verify username/password, decrypt DEK into memory, and return user_id or None."""
    conn = get_db()
    row = conn.execute(
        "SELECT id, password_hash, dek_salt, encrypted_dek FROM users WHERE username = ?",
        (username,)
    ).fetchone()
    if not row or not bcrypt.checkpw(password.encode('utf-8'), row['password_hash'].encode('utf-8')):
        return None

    user_id = row['id']
    try:
        salt = base64.urlsafe_b64decode(row['dek_salt'].encode())
        dek, legacy = decrypt_dek_with_fallback(row['encrypted_dek'], password, salt)
        set_user_dek(user_id, dek)
        if legacy:
            # Migrate to current PBKDF2 iterations.
            new_salt = secrets.token_bytes(16)
            new_encrypted_dek = encrypt_dek(dek, password, new_salt)
            conn.execute(
                "UPDATE users SET dek_salt = ?, encrypted_dek = ? WHERE id = ?",
                (base64.urlsafe_b64encode(new_salt).decode(), new_encrypted_dek, user_id)
            )
            conn.commit()
    except Exception as e:
        from flask import current_app
        current_app.logger.error(f'Failed to decrypt DEK for user {user_id}: {e}')
        clear_user_dek(user_id)
        return None
    return user_id
