"""Data Encryption Key (DEK) in-memory cache and field encryption."""
from __future__ import annotations

import base64
import secrets
import threading
from typing import Optional

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from openmail.config import PBKDF2_ITERATIONS, PBKDF2_ITERATIONS_LEGACY
from .kdf import derive_key


# Per-process in-memory cache of decrypted DEKs, keyed by user_id.
# Cleared on server restart by design.
_USER_DEKS: dict[int, bytes] = {}
_lock = threading.RLock()


def get_user_dek(user_id: int | None) -> bytes | None:
    if user_id is None:
        return None
    with _lock:
        return _USER_DEKS.get(user_id)


def set_user_dek(user_id: int, dek: bytes) -> None:
    with _lock:
        _USER_DEKS[user_id] = dek


def clear_user_dek(user_id: int | None) -> None:
    if user_id is None:
        return
    with _lock:
        _USER_DEKS.pop(user_id, None)


def user_unlocked(user_id: int | None) -> bool:
    if user_id is None:
        return False
    with _lock:
        return user_id in _USER_DEKS


def _decrypt_dek(ciphertext: str, password: str, salt: bytes, iterations: int) -> bytes:
    key = derive_key(password, salt, iterations)
    aes = AESGCM(key)
    pad = 4 - (len(ciphertext) % 4)
    if pad != 4:
        ciphertext += '=' * pad
    data = base64.urlsafe_b64decode(ciphertext.encode())
    nonce = data[:12]
    ct = data[12:]
    return aes.decrypt(nonce, ct, None)


def decrypt_dek_with_fallback(ciphertext: str, password: str, salt: bytes) -> tuple[bytes, bool]:
    """Decrypt DEK using current iterations; fall back to legacy count on InvalidTag.
    Returns (dek, was_legacy).
    """
    try:
        return _decrypt_dek(ciphertext, password, salt, PBKDF2_ITERATIONS), False
    except InvalidTag:
        return _decrypt_dek(ciphertext, password, salt, PBKDF2_ITERATIONS_LEGACY), True


def encrypt_dek(dek: bytes, password: str, salt: bytes, iterations: int | None = None) -> str:
    key = derive_key(password, salt, iterations)
    aes = AESGCM(key)
    nonce = secrets.token_bytes(12)
    ct = aes.encrypt(nonce, dek, None)
    return base64.urlsafe_b64encode(nonce + ct).decode().rstrip('=')


def encrypt_email_field(value: str | None, user_id: int | None = None) -> str | None:
    if value is None:
        return None
    dek = get_user_dek(user_id)
    if dek is None:
        raise RuntimeError('Encryption key not available. User must log in.')
    aes = AESGCM(dek)
    nonce = secrets.token_bytes(12)
    ct = aes.encrypt(nonce, value.encode('utf-8'), None)
    return base64.urlsafe_b64encode(nonce + ct).decode().rstrip('=')


def decrypt_email_field(token: str | None, user_id: int | None = None) -> str | None:
    if token is None:
        return None
    dek = get_user_dek(user_id)
    if dek is None:
        # If DEK is missing, the server was restarted; caller should require re-login.
        raise RuntimeError('Server locked: encryption key not available.')
    aes = AESGCM(dek)
    pad = 4 - (len(token) % 4)
    if pad != 4:
        token += '=' * pad
    data = base64.urlsafe_b64decode(token.encode())
    nonce = data[:12]
    ct = data[12:]
    return aes.decrypt(nonce, ct, None).decode('utf-8')
