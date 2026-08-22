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
    data = request.json or {}
    if 'email' in data:
        data['email'] = (data.get('email') or '').strip().lower()
    contact = contact_service.update_contact(contact_id, data)
    if not contact:
        return jsonify({"error": "No valid fields or not found"}), 400
    return jsonify(contact)


@bp.route("/contacts/<int:contact_id>", methods=["DELETE"])
@login_required
def delete_contact_route(contact_id: int):
    contact_service.delete_contact(contact_id)
    return jsonify({"deleted": True})


@bp.route("/starred-addresses", methods=["GET"])
@login_required
def list_starred_addresses_route():
    return jsonify({"addresses": contact_service.list_starred_addresses()})


@bp.route("/starred-addresses", methods=["POST"])
@login_required
def add_starred_address_route():
    data = request.json or {}
    email = (data.get("email") or "").strip().lower()
    if not email:
        return jsonify({"error": "Email required"}), 400
    result, status = contact_service.add_starred_address(email)
    return jsonify(result), status


@bp.route("/starred-addresses", methods=["DELETE"])
@login_required
def remove_starred_address_route():
    data = request.json or {}
    email = (data.get("email") or "").strip().lower()
    if not email:
        return jsonify({"error": "Email required"}), 400
    result, status = contact_service.remove_starred_address(email)
    return jsonify(result), status


@bp.route("/contacts/exists", methods=["GET"])
@login_required
def contact_exists_route():
    email = (request.args.get("email") or "").strip().lower()
    if not email:
        return jsonify({"error": "Email required"}), 400
    return jsonify({"exists": contact_service.contact_exists(email)})


@bp.route("/domain-rules", methods=["GET"])
@login_required
def list_domain_rules_route():
    return jsonify(contact_service.list_domain_rules())


@bp.route("/domain-rules", methods=["POST"])
@login_required
def create_domain_rule_route():
    data = request.json or {}
    domain = (data.get('domain') or '').strip().lower()
    result, status = contact_service.create_domain_rule(domain, data.get('action', 'star'), data.get('enabled', True))
    return jsonify(result), status


@bp.route("/domain-rules/<int:rule_id>", methods=["PATCH"])
@login_required
def update_domain_rule_route(rule_id: int):
    result = contact_service.update_domain_rule(rule_id, request.json or {})
    if result is None:
        return jsonify({"error": "No valid fields or not found"}), 400
    return jsonify(result)


@bp.route("/domain-rules/<int:rule_id>", methods=["DELETE"])
@login_required
def delete_domain_rule_route(rule_id: int):
    return jsonify({"deleted": contact_service.delete_domain_rule(rule_id)})
