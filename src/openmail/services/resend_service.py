"""Resend API integration: send, sync, webhook processing."""
from __future__ import annotations

import base64
import json
import logging
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import requests

logger = logging.getLogger(__name__)

_ASCII_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z0-9-]+$")


def _validate_email_address(addr: str) -> str | None:
    """Return normalized ASCII email or None if invalid."""
    if not addr:
        return None
    addr = addr.strip()
    if not addr:
        return None
    if not addr.isascii():
        return None
    if "@" not in addr or " " in addr:
        return None
    if not _ASCII_EMAIL_RE.match(addr):
        return None
    return addr

from openmail.config import RESEND_API_KEY, FROM_EMAIL, FROM_NAME
from openmail.db import get_db
from openmail.auth.current_user import current_user_id
from openmail.auth.users import get_user_by_email, get_user_from_address
from openmail.crypto.dek import encrypt_email_field
from openmail.utils.email import (
    parse_inbound_event,
    fetch_resend_email,
    is_spam,
    download_attachments,
)
from openmail import sse


_executor: ThreadPoolExecutor | None = None


def get_executor() -> ThreadPoolExecutor:
    global _executor
    if _executor is None or _executor._shutdown:
        _executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="resend_worker")
    return _executor


def _resolve_email_id(payload: dict) -> str | None:
    data = payload.get("data", {})
    return data.get("email_id") or data.get("id")


def _process_inbound_email(payload: dict, user_id: int) -> dict | None:
    """Parse, fetch, classify and insert inbound email. Caller must commit.

    Inbound emails are stored as plain text because the webhook is not
    authenticated as the recipient user, so the per-user DEK is unavailable.
    The decrypt_email_field helper already falls back to plaintext on failure,
    so the email displays correctly once the user logs in.
    """
    conn = get_db()
    parsed = parse_inbound_event(payload)
    email_id = parsed["resend_id"]
    if not email_id:
        return None

    existing = conn.execute(
        "SELECT id, user_id FROM emails WHERE resend_id = ?",
        (email_id,)
    ).fetchone()
    if existing:
        # Already imported by webhook or a previous sync; skip duplicate.
        return None

    full_email = fetch_resend_email(email_id, RESEND_API_KEY) if RESEND_API_KEY else {}
    body_text = full_email.get("text") if full_email else ""
    body_html = full_email.get("html") if full_email else ""
    if not body_text and not body_html:
        body_text = full_email.get("subject", "")

    spam = is_spam(parsed["subject"], body_text, parsed["sender_email"] or "")
    folder = "spam" if spam else "inbox"
    preview = (body_text or "")[:300]

    from openmail.services.contact_service import is_starred_address, is_domain_rule_enabled
    auto_starred = 1 if (not spam and parsed["sender_email"] and (
        is_starred_address(user_id, parsed["sender_email"])
        or is_domain_rule_enabled(user_id, parsed["sender_email"])
    )) else 0

    conn.execute(
        """INSERT INTO emails
        (user_id, resend_id, direction, folder, sender_name, sender_email, recipient,
         subject, preview, body_text, body_html, is_spam, is_starred, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            user_id,
            parsed["resend_id"],
            parsed["direction"],
            folder,
            parsed["sender_name"],
            parsed["sender_email"],
            parsed["recipient"],
            parsed["subject"],
            preview,
            body_text or None,
            body_html or None,
            1 if spam else 0,
            auto_starred,
            parsed["created_at"],
        ),
    )
    email_row_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    # Attachments
    saved = download_attachments(parsed.get("attachments", []), email_row_id)
    if saved:
        attachments_json = json.dumps(saved)
        conn.execute(
            "UPDATE emails SET attachments = ? WHERE id = ?",
            (attachments_json, email_row_id)
        )

    return {"id": email_row_id, "is_spam": spam, "subject": parsed["subject"]}


def _resolve_recipient(payload: dict) -> str | None:
    """Extract the first clean To email address from a Resend webhook payload."""
    from email.utils import parseaddr
    data = payload.get("data", {})
    to = data.get("to", [])
    raw = None
    if isinstance(to, list) and to:
        raw = to[0]
    elif isinstance(to, str):
        raw = to
    if not raw:
        return None
    _, email = parseaddr(raw)
    return email or raw


def process_inbound_webhook(payload: dict) -> dict:
    """Synchronous webhook handler. Runs in request thread."""
    if payload.get("type") != "email.received":
        return {"ok": True, "id": None, "new": False}

    recipient = _resolve_recipient(payload)
    user = get_user_by_email(recipient) if recipient else None
    user_id = user["id"] if user else (current_user_id() or 1)

    try:
        conn = get_db()
        result = _process_inbound_email(payload, user_id)
        conn.commit()
        if result:
            sse.notify("new_email", result)
            return {"ok": True, "id": result["id"], "new": True}
        return {"ok": True, "id": None, "new": False}
    except RuntimeError:
        logger.error(f"DEK missing for user {user_id}, cannot store inbound email")
        return {"error": "Server locked", "code": "dek_missing"}


def send_email(to: str, subject: str, body: str, attachments: list[dict], user_id: int | None = None) -> dict:
    if not RESEND_API_KEY:
        return {"error": "RESEND_API_KEY not configured"}

    if user_id is None:
        user_id = current_user_id() or 1
    from_email, from_name = get_user_from_address(user_id)
    from_header = from_email if not from_name else f"{from_name} <{from_email}>"
    resend_attachments = []
    for att in attachments:
        filename = att.get("filename", "attachment.bin")
        content = att.get("content", "")
        content_type = att.get("content_type", "application/octet-stream")
        if content:
            resend_attachments.append({
                "filename": filename,
                "content": content,
                "content_type": content_type,
            })

    params: dict[str, Any] = {
        "from": from_header,
        "to": to,
        "subject": subject,
        "text": body,
    }
    if resend_attachments:
        params["attachments"] = resend_attachments

    import resend
    resend.api_key = RESEND_API_KEY
    result = resend.Emails.send(params)

    # Resend SDK may return an object with attributes instead of a dict.
    if not isinstance(result, dict):
        result = {"id": getattr(result, "id", None)}

    if not result.get("id"):
        raise RuntimeError(f"Resend send failed or returned no id: {result!r}")

    # Persist outbound copy
    preview = (body or "")[:300]
    attachments_json = json.dumps([
        {"filename": a["filename"], "content_type": a["content_type"]}
        for a in resend_attachments
    ]) if resend_attachments else "[]"

    conn = get_db()
    conn.execute(
        """INSERT INTO emails
        (user_id, resend_id, direction, folder, sender_email, sender_name, recipient, subject, preview,
         body_text, is_read, created_at)
        VALUES (?, ?, 'outbound', 'sent', ?, ?, ?, ?, ?, ?, 1, datetime('now'))""",
        (
            user_id,
            result.get("id"),
            encrypt_email_field(from_email, user_id),
            encrypt_email_field(from_name, user_id),
            encrypt_email_field(to, user_id),
            encrypt_email_field(subject, user_id),
            encrypt_email_field(preview, user_id),
            encrypt_email_field(body or None, user_id),
        )
    )
    email_row_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    if resend_attachments:
        conn.execute(
            "UPDATE emails SET attachments = ? WHERE id = ?",
            (attachments_json, email_row_id)
        )
    conn.commit()
    return {"status": "sent", "provider": "resend", "id": result.get("id")}


def sync_emails() -> dict:
    if not RESEND_API_KEY:
        return {"error": "RESEND_API_KEY not configured"}
    headers = {"Authorization": f"Bearer {RESEND_API_KEY}"}
    resp = requests.get(
        "https://api.resend.com/emails/receiving",
        headers=headers,
        params={"limit": 50},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json().get("data", [])
    imported = 0
    conn = get_db()
    for item in data:
        email_id = item.get("id")
        if not email_id:
            continue
        to_list = item.get("to", [])
        recipient = to_list[0] if isinstance(to_list, list) and to_list else (to_list if isinstance(to_list, str) else None)
        user = get_user_by_email(recipient) if recipient else None
        user_id = user["id"] if user else (current_user_id() or 1)

        webhook_payload = {
            "type": "email.received",
            "data": {
                "email_id": email_id,
                "id": email_id,
                "from": item.get("from"),
                "to": item.get("to", []),
                "subject": item.get("subject"),
                "created_at": item.get("created_at"),
            }
        }
        try:
            result = _process_inbound_email(webhook_payload, user_id)
            if result:
                imported += 1
        except RuntimeError:
            logger.error(f"DEK missing during sync for email {email_id}")
            continue
    conn.commit()
    return {"imported": imported}


