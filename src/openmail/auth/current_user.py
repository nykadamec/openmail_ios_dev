"""Resolve current authenticated user with session + CF Access caching."""
from __future__ import annotations

from typing import Optional

from flask import request, g, jsonify, make_response

from openmail.auth.session import get_session, current_session_id, create_session
from openmail.auth.cf_access import auto_login_from_cf_access
from openmail.crypto.dek import user_unlocked
from openmail.db import get_db


def current_user_id() -> Optional[int]:
    """Return current user id from session or CF Access without side effects."""
    user = current_user()
    if user:
        return user['id']
    if g.get('_cf_user_id'):
        return g['_cf_user_id']
    cf_id = auto_login_from_cf_access()
    if cf_id:
        g['_cf_user_id'] = cf_id
        return cf_id
    return None


def current_user() -> Optional[dict]:
    """Return current authenticated user or None, with request-level cache."""
    if hasattr(g, 'current_user'):
        return g.current_user
    sid = current_session_id()
    session = get_session(sid)
    user = None
    if session:
        conn = get_db()
        row = conn.execute(
            "SELECT id, username FROM users WHERE id = ?",
            (session['user_id'],)
        ).fetchone()
        if row:
            user = dict(row)
    if not user:
        cf_user_id = auto_login_from_cf_access()
        if cf_user_id:
            new_sid = create_session(cf_user_id)
            request._cf_session_id = new_sid
            conn = get_db()
            row = conn.execute(
                "SELECT id, username FROM users WHERE id = ?", (cf_user_id,)
            ).fetchone()
            if row:
                user = dict(row)
    g.current_user = user
    return user


def login_required(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*args, **kwargs):
        user = current_user()
        if not user:
            if request.is_json or request.path.startswith('/api/'):
                return jsonify({"error": "Unauthorized"}), 401
            return jsonify({"error": "Unauthorized"}), 401
        if not user_unlocked(user.get('id')):
            sid = current_session_id()
            from openmail.auth.session import delete_session
            from openmail.crypto.dek import clear_user_dek
            delete_session(sid)
            clear_user_dek(user.get('id'))
            resp = make_response(jsonify({'error': 'Locked', 'code': 'dek_missing'}))
            resp.delete_cookie('session_id')
            return resp, 401
        return f(*args, **kwargs)
    return wrapped
