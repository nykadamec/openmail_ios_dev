"""Email and SSE routes."""
from __future__ import annotations

from flask import Blueprint, request, jsonify, send_file

from openmail.auth.current_user import login_required
from openmail.services import email_service, resend_service
from openmail import sse


bp = Blueprint('emails', __name__, url_prefix='/api')


@bp.route("/events")
@login_required
def sse_stream():
    return sse.stream()


@bp.route("/emails", methods=["GET"])
@login_required
def list_emails_route():
    folder = request.args.get("folder")  # no default; special folders ignore it
    direction = request.args.get("direction", "inbound")
    starred = request.args.get("starred", type=int)
    is_spam = request.args.get("is_spam", type=int)
    is_trash = request.args.get("is_trash", type=int)
    custom_folder_id = request.args.get("custom_folder_id", type=int)
    q = request.args.get("q")
    limit = request.args.get("limit", 50, type=int)
    offset = request.args.get("offset", 0, type=int)
    # Default to inbox only when no special filter is active
    if q is None and folder is None and starred is None and is_spam is None and is_trash is None and custom_folder_id is None:
        folder = "inbox"
    return jsonify(email_service.list_emails(
        folder=folder or '',
        direction=direction,
        starred=starred,
        is_spam=is_spam,
        is_trash=is_trash,
        custom_folder_id=custom_folder_id,
        q=q,
        limit=limit,
        offset=offset,
    ))


@bp.route("/emails/<int:email_id>", methods=["GET"])
@login_required
def get_email_route(email_id: int):
    email = email_service.get_email(email_id)
    if not email:
        return jsonify({"error": "Email not found"}), 404
    return jsonify(email)


@bp.route("/emails/<int:email_id>", methods=["DELETE"])
@login_required
def delete_email_route(email_id: int):
    email_service.move_to_trash(email_id)
    return jsonify({"deleted": True})


@bp.route("/emails/<int:email_id>", methods=["PATCH"])
@login_required
def update_email_route(email_id: int):
    email = email_service.update_email(email_id, request.json or {})
    if not email:
        return jsonify({"error": "No valid fields or not found"}), 400
    return jsonify(email)


@bp.route("/emails/bulk", methods=["POST"])
@login_required
def bulk_email_action_route():
    data = request.json or {}
    ids = data.get("ids", [])
    action = data.get("action", "")
    count = email_service.bulk_action(ids, action)
    return jsonify({"ok": True, "count": count})


@bp.route("/send", methods=["POST"])
@login_required
def send_email_route():
    data = request.json or {}
    to = data.get("to", "").strip()
    subject = data.get("subject", "").strip()
    body = data.get("body", "")
    if not to or not subject:
        return jsonify({"error": "Missing recipient or subject"}), 400
    result = resend_service.send_email(to, subject, body, data.get("attachments", []))
    if result.get("error"):
        return jsonify({"error": result["error"]}), 500
    return jsonify(result)


@bp.route("/sync", methods=["POST"])
@login_required
def sync_emails_route():
    result = resend_service.sync_emails()
    if result.get("error"):
        return jsonify({"error": result["error"]}), 500
    return jsonify(result)


@bp.route("/inbound", methods=["POST"])
def inbound_webhook_route():
    payload = request.get_json(silent=True) or {}
    result = resend_service.process_inbound_webhook(payload)
    if isinstance(result, tuple):
        return jsonify(result[0]), result[1]
    return jsonify(result)


@bp.route("/attachments/<int:email_id>/<path:filename>")
@login_required
def get_attachment_route(email_id: int, filename: str):
    attachment = email_service.get_attachment(email_id, filename)
    if attachment is None:
        return jsonify({"error": "Attachment not found"}), 404

    content_type = attachment['content_type']
    base_content_type = content_type.split(';', 1)[0].strip().lower()
    force_download = request.args.get('download') == '1'
    inline_types = (
        base_content_type == 'application/pdf'
        or (base_content_type.startswith('image/') and base_content_type != 'image/svg+xml')
        or base_content_type in {
            'text/plain',
            'text/csv',
            'text/markdown',
            'text/tab-separated-values',
        }
    )
    return send_file(
        str(attachment['path']),
        mimetype=content_type,
        as_attachment=force_download or not inline_types,
        download_name=attachment['filename'],
    )
