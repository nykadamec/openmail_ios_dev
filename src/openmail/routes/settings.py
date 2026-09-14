"""Settings-related API routes."""
from __future__ import annotations

from flask import Blueprint, request, jsonify

from openmail.auth.current_user import current_user, login_required
from openmail.auth.users import get_user_by_id, update_user_profile

bp = Blueprint('settings', __name__, url_prefix='/api')

# Currently password change lives in auth.py; this module hosts profile settings.


@bp.route("/profile", methods=["PATCH"])
@login_required
def update_profile():
    user = current_user()
    data = request.get_json(silent=True) or {}

    def _opt(field: str) -> str | None:
        if field not in data:
            return None
        val = data.get(field)
        if val is None:
            return ""
        if not isinstance(val, str):
            return str(val)
        return val

    first_name = _opt("first_name")
    last_name = _opt("last_name")
    phone = _opt("phone")

    try:
        updated = update_user_profile(user['id'], first_name, last_name, phone)
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    if not updated:
        return jsonify({"error": "User not found"}), 404
    full = get_user_by_id(user['id']) or updated
    return jsonify({
        "id": full['id'],
        "username": full['username'],
        "email": full['email'],
        "from_name": full['from_name'],
        "first_name": full.get('first_name'),
        "last_name": full.get('last_name'),
        "phone": full.get('phone'),
    }), 200
