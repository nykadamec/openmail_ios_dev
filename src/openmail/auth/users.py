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
        "SELECT id, username, email, from_name FROM users WHERE id = ?",
        (user_id,)
    ).fetchone()
    return dict(row) if row else None


def get_user_by_email(email: str) -> dict | None:
    """Return user dict by email address, or None."""
    conn = get_db()
    row = conn.execute(
        "SELECT id, username, email, from_name FROM users WHERE LOWER(email) = LOWER(?)",
        (email,)
    ).fetchone()
    return dict(row) if row else None


def get_user_from_address(user_id: int) -> tuple[str, str]:
    """Return (email, from_name) for a user, falling back to global config."""
    from openmail.config import FROM_EMAIL, FROM_NAME
    user = get_user_by_id(user_id)
    email = (user.get('email') or FROM_EMAIL) if user else FROM_EMAIL
    name = (user.get('from_name') or FROM_NAME) if user else FROM_NAME
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
