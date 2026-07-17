"""Contacts API routes."""
from __future__ import annotations

from flask import Blueprint, request, jsonify

from openmail.auth.current_user import login_required
from openmail.services import contact_service


bp = Blueprint('contacts', __name__, url_prefix='/api')


@bp.route("/contacts", methods=["GET"])
@login_required
def list_contacts_route():
    q = (request.args.get("q") or "").lower()
    return jsonify(contact_service.list_contacts(q))


@bp.route("/contacts", methods=["POST"])
@login_required
def create_contact_route():
    data = request.json or {}
    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip().lower()
    notes = data.get("notes")
    if not name or not email:
        return jsonify({"error": "Name and email required"}), 400
    result, status = contact_service.create_contact(name, email, notes)
    return jsonify(result), status


@bp.route("/contacts/<int:contact_id>", methods=["PATCH"])
@login_required
def update_contact_route(contact_id: int):
    contact = contact_service.update_contact(contact_id, request.json or {})
    if not contact:
        return jsonify({"error": "No valid fields or not found"}), 400
    return jsonify(contact)


@bp.route("/contacts/<int:contact_id>", methods=["DELETE"])
@login_required
def delete_contact_route(contact_id: int):
    contact_service.delete_contact(contact_id)
    return jsonify({"deleted": True})
