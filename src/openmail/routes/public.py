"""Public routes: index, setup, login, logout, sw.js, manifest."""
from __future__ import annotations

from flask import Blueprint, render_template, request, make_response, redirect, url_for, send_from_directory, jsonify

from openmail.config import FROM_EMAIL
from openmail.db import get_db
from openmail.auth.users import has_users, create_user, verify_user
from openmail.auth.session import create_session, delete_session
from openmail.auth.current_user import current_user
from openmail.crypto.dek import clear_user_dek


bp = Blueprint('public', __name__)


def _set_session_cookie(resp, sid: str) -> None:
    resp.set_cookie('session_id', sid, httponly=True, samesite='Lax', max_age=15*60)


@bp.route("/sw.js")
def service_worker():
    return send_from_directory(".", "sw.js", mimetype="application/javascript")


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
        sid = create_session(user_id)
        resp = make_response(redirect(url_for('public.index')))
        _set_session_cookie(resp, sid)
        return resp
    return render_template("setup.html")


@bp.route("/login", methods=["GET", "POST"])
def login_page():
    user = current_user()
    if user:
        resp = make_response(redirect(url_for('public.index')))
        if hasattr(request, '_cf_session_id'):
            _set_session_cookie(resp, request._cf_session_id)
        return resp
    if request.method == "POST":
        data = request.form if request.form else (request.json or {})
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""
        user_id = verify_user(username, password)
        if not user_id:
            return render_template("login.html", error="Invalid credentials"), 401
        sid = create_session(user_id)
        resp = make_response(redirect(url_for('public.index')))
        _set_session_cookie(resp, sid)
        return resp
    return render_template("login.html")


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
    from openmail.auth.current_user import current_user, login_required
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
    return jsonify(user)
