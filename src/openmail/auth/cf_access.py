"""Cloudflare Access (Zero Trust) JWT verification and auto-provisioning."""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from typing import Optional

import bcrypt
import jwt
import requests
from cryptography.hazmat.primitives import serialization
from flask import current_app, request

from openmail.config import CF_ACCESS_ENABLED, CF_TEAM_DOMAIN, CF_AUD_TAG
from openmail.db import get_db
from openmail.auth.users import create_user


_CF_ACCESS_PUBLIC_KEYS: list = []
_CF_ACCESS_KEYS_LOADED_AT: Optional[datetime] = None


def _load_cf_access_keys() -> None:
    global _CF_ACCESS_PUBLIC_KEYS, _CF_ACCESS_KEYS_LOADED_AT
    if not CF_TEAM_DOMAIN:
        return
    now = datetime.now(timezone.utc)
    if _CF_ACCESS_KEYS_LOADED_AT and (now - _CF_ACCESS_KEYS_LOADED_AT) < timedelta(hours=1):
        return
    try:
        url = f'https://{CF_TEAM_DOMAIN}/cdn-cgi/access/certs'
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        certs = r.json()
        keys = []
        for cert in certs.get('keys', []):
            try:
                key = serialization.load_pem_public_key(cert['public_key'].encode())
                keys.append(key)
            except Exception:
                continue
        _CF_ACCESS_PUBLIC_KEYS = keys
        _CF_ACCESS_KEYS_LOADED_AT = now
    except Exception:
        _CF_ACCESS_PUBLIC_KEYS = []


def verify_cf_access_token(token: str) -> Optional[dict]:
    if not token or not CF_TEAM_DOMAIN or not CF_AUD_TAG:
        return None
    _load_cf_access_keys()
    for key in _CF_ACCESS_PUBLIC_KEYS:
        try:
            payload = jwt.decode(
                token,
                key,
                algorithms=['RS256'],
                audience=CF_AUD_TAG,
                options={'require': ['exp', 'iat', 'sub', 'aud']},
            )
            return payload
        except jwt.InvalidTokenError:
            continue
    return None


def get_cf_access_email() -> Optional[str]:
    token = request.headers.get('Cf-Access-Jwt-Assertion')
    if not token:
        return None
    payload = verify_cf_access_token(token)
    if not payload:
        return None
    return payload.get('email') or payload.get('sub')


def auto_login_from_cf_access() -> Optional[int]:
    if not CF_ACCESS_ENABLED:
        return None
    email = get_cf_access_email()
    if not email:
        return None
    username = email.split('@')[0].lower()
    conn = get_db()
    row = conn.execute('SELECT id FROM users WHERE username = ?', (username,)).fetchone()
    if not row:
        # Auto-provision a local user for this Cloudflare-authenticated email.
        temp_pw = bcrypt.hashpw(secrets.token_hex(32).encode(), bcrypt.gensalt(rounds=12)).decode()
        cur = conn.execute(
            'INSERT INTO users (username, password_hash) VALUES (?, ?)',
            (username, temp_pw)
        )
        user_id = cur.lastrowid
        conn.commit()
    else:
        user_id = row['id']
    return user_id
