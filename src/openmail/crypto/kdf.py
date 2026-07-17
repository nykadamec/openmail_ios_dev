"""Password-derived key encryption key (KEK) helpers."""
from __future__ import annotations

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

from openmail.config import PBKDF2_ITERATIONS, PBKDF2_ITERATIONS_LEGACY


def derive_key(password: str, salt: bytes, iterations: int | None = None) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=iterations or PBKDF2_ITERATIONS,
    )
    return kdf.derive(password.encode('utf-8'))
