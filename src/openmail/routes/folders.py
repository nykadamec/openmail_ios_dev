"""Folder API routes."""
from __future__ import annotations

from flask import Blueprint, request, jsonify

from openmail.auth.current_user import login_required
from openmail.services import folder_service, stats_service


bp = Blueprint('folders', __name__, url_prefix='/api')


@bp.route("/folders", methods=["GET"])
@login_required
def list_folders_route():
    return jsonify(folder_service.list_folders())


@bp.route("/custom_folders", methods=["POST"])
@login_required
def create_custom_folder_route():
    data = request.json or {}
    name = (data.get("name") or "").strip()
    color = data.get("color", "#3B82F6")
    icon = data.get("icon", "📁")
    if not name:
        return jsonify({"error": "Name required"}), 400
    result, status = folder_service.create_folder(name, color, icon)
    return jsonify(result), status


@bp.route("/custom_folders/<int:folder_id>", methods=["DELETE"])
@login_required
def delete_custom_folder_route(folder_id: int):
    folder_service.delete_folder(folder_id)
    return jsonify({"deleted": True})


@bp.route("/stats", methods=["GET"])
@login_required
def stats_route():
    return jsonify(stats_service.get_stats())
