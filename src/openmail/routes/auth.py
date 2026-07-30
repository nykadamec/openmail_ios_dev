"""Auth-related API routes: locale, change password."""
from __future__ import annotations

import base64
import secrets

import bcrypt
from flask import Blueprint, request, jsonify, make_response

from openmail.auth.current_user import current_user, login_required
from openmail.auth.users import verify_user
from openmail.auth.session import delete_session, current_session_id
from openmail.db import get_db
from openmail.crypto.dek import (
    encrypt_dek,
    decrypt_dek_with_fallback,
    set_user_dek,
    clear_user_dek,
)
from openmail.i18n import t, get_locale, set_locale, get_all_keys


bp = Blueprint('auth', __name__, url_prefix='/api')


@bp.route("/locale", methods=["GET", "POST"])
def api_locale():
    if request.method == "POST":
        data = request.json or {}
        lang = data.get("locale", "cs")
        set_locale(lang)
        resp = jsonify({"locale": get_locale()})
        resp.set_cookie("locale", lang, max_age=365*24*3600, samesite="Lax")
        return resp
    return jsonify({"locale": get_locale(), "data": get_all_keys()})


@bp.route("/change_password", methods=["POST"])
@login_required
def change_password():
    user = current_user()
    user_id = user['id']
    data = request.json or {}
    current_pw = data.get("current_password") or ""
    new_pw = data.get("new_password") or ""
    if len(new_pw) < 6:
        return jsonify({"error": t("error.password_short")}), 400
    if not verify_user(user['username'], current_pw):
        return jsonify({"error": t("error.password_wrong")}), 401

    conn = get_db()
    row = conn.execute(
        "SELECT dek_salt, encrypted_dek FROM users WHERE id = ?",
        (user_id,)
    ).fetchone()
    try:
        salt = base64.urlsafe_b64decode(row['dek_salt'].encode())
        dek, _ = decrypt_dek_with_fallback(row['encrypted_dek'], current_pw, salt)
        new_salt = secrets.token_bytes(16)
        new_encrypted_dek = encrypt_dek(dek, new_pw, new_salt)
    except Exception as e:
        from flask import current_app
        current_app.logger.error(f'Failed to re-encrypt DEK during password change: {e}')
        return jsonify({"error": t("error.encryption")}), 500

    new_hash = bcrypt.hashpw(new_pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    conn.execute(
        "UPDATE users SET password_hash = ?, dek_salt = ?, encrypted_dek = ? WHERE id = ?",
        (new_hash, base64.urlsafe_b64encode(new_salt).decode(), new_encrypted_dek, user_id)
    )
    conn.commit()
    set_user_dek(user_id, dek)
    return jsonify({"status": "changed"})


@bp.route("/logout", methods=["POST"])
def api_logout():
    user = current_user()
    if user:
        clear_user_dek(user['id'])
    sid = current_session_id()
    delete_session(sid)
    resp = make_response(jsonify({"status": "logged_out"}))
    resp.delete_cookie('session_id')
    return resp
