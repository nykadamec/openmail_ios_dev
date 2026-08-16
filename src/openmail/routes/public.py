"""Public routes: index, setup, login, logout, sw.js, manifest."""
from __future__ import annotations

from pathlib import Path

from flask import Blueprint, render_template, request, make_response, redirect, url_for, send_from_directory, jsonify

from openmail.config import FROM_EMAIL, REMEMBER_ME_DAYS, REMEMBER_USERNAME_DAYS, FLASK_DEBUG
from openmail.db import get_db
from openmail.auth.users import has_users, create_user, verify_user, get_user_by_id
from openmail.auth.session import create_session, delete_session
from openmail.auth.current_user import current_user, login_required
from openmail.crypto.dek import clear_user_dek
from openmail.services import email_service


bp = Blueprint('public', __name__)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent


def _set_session_cookie(resp, sid: str, remember: bool = False) -> None:
    max_age = REMEMBER_ME_DAYS * 24 * 3600 if remember else 15 * 60
    resp.set_cookie(
        'session_id', sid,
        httponly=True, samesite='Lax', secure=not FLASK_DEBUG,
        max_age=max_age,
    )


def _set_remember_username_cookie(resp, username: str | None) -> None:
    if username:
        resp.set_cookie(
            'remember_username', username,
            httponly=True, samesite='Lax', secure=not FLASK_DEBUG,
            max_age=REMEMBER_USERNAME_DAYS * 24 * 3600,
        )
    else:
        resp.delete_cookie('remember_username')


@bp.route("/sw.js")
def service_worker():
    return send_from_directory(str(REPO_ROOT), "sw.js", mimetype="application/javascript")


@bp.route("/setup", methods=["GET", "POST"])
def setup():
    if has_users():
        return redirect(url_for('public.login_page'))
    if request.method == "POST":
        data = request.form if request.form else (request.json or {})
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""
        if not username or len(password) < 6:
            return render_template("setup.html", error="Username required, password min 6 chars"), 400
        user_id = create_user(username, password)
        sid = create_session(user_id, remember=False)
        resp = make_response(redirect(url_for('public.index')))
        _set_session_cookie(resp, sid, remember=False)
        return resp
    return render_template("setup.html")


@bp.route("/login", methods=["GET", "POST"])
def login_page():
    user = current_user()
    if user:
        resp = make_response(redirect(url_for('public.index')))
        if hasattr(request, '_cf_session_id'):
            _set_session_cookie(resp, request._cf_session_id, remember=False)
        return resp
    remember_username = request.cookies.get('remember_username') or ""
    if request.method == "POST":
        data = request.form if request.form else (request.json or {})
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""
        remember_me = bool(data.get("remember_me"))
        remember_username_flag = bool(data.get("remember_username"))
        user_id = verify_user(username, password)
        if not user_id:
            return render_template(
                "login.html",
                error="Invalid credentials",
                remember_username=remember_username,
            ), 401
        sid = create_session(user_id, remember=remember_me)
        resp = make_response(redirect(url_for('public.index')))
        _set_session_cookie(resp, sid, remember=remember_me)
        _set_remember_username_cookie(resp, username if remember_username_flag else None)
        return resp
    return render_template("login.html", remember_username=remember_username)


@bp.route("/logout", methods=["POST", "GET"])
def logout():
    from openmail.auth.current_user import current_user_id
    sid = request.cookies.get('session_id')
    if sid:
        session = get_db().execute("SELECT user_id FROM sessions WHERE id = ?", (sid,)).fetchone()
        if session:
            clear_user_dek(session['user_id'])
        delete_session(sid)
    resp = make_response(redirect(url_for('public.login_page')))
    resp.delete_cookie('session_id')
    return resp


@bp.route("/")
def index():
    user = current_user()
    if not user:
        return redirect(url_for('public.login_page'))
    resp = make_response(render_template("index.html", from_email=FROM_EMAIL))
    if hasattr(request, '_cf_session_id'):
        _set_session_cookie(resp, request._cf_session_id)
    return resp


@bp.route("/api/me")
def me():
    from openmail.crypto.dek import user_unlocked
    user = current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    if not user_unlocked(user.get('id')):
        sid = request.cookies.get('session_id')
        delete_session(sid)
        clear_user_dek(user.get('id'))
        resp = jsonify({'error': 'Locked', 'code': 'dek_missing'})
        resp.delete_cookie('session_id')
        return resp, 401
    full = get_user_by_id(user['id'])
    if not full:
        return jsonify({"error": "User not found"}), 404
    return jsonify({
        "id": full['id'],
        "username": full['username'],
        "email": full['email'],
        "from_name": full['from_name'],
    })


@bp.route("/email/<int:email_id>")
@login_required
def email_detail(email_id: int):
    email = email_service.get_email(email_id)
    if not email:
        return redirect(url_for('public.index'))
    return render_template("email.html", email=email, from_email=FROM_EMAIL)
