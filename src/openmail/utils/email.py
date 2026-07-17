"""Email parsing and spam classification helpers."""
from __future__ import annotations

import email
import json
import re
from email.header import decode_header
from email.utils import parseaddr
from pathlib import Path
from typing import Any

import requests

from openmail.utils.time import now_iso


SPAM_KEYWORDS = [
    'viagra', 'cialis', 'lottery', 'winner', 'click here', 'free money',
    'make money fast', 'nigerian prince', 'bitcoin investment', 'crypto giveaway',
    'weight loss', 'miracle', 'limited time offer', 'act now',
    'congratulations you', 'you have been selected', 'claim your prize',
    'suspend your account', 'verify your password immediately',
]


def decode_value(value: str | None) -> str:
    if value is None:
        return ""
    decoded, charset = decode_header(value)[0]
    if isinstance(decoded, bytes):
        try:
            return decoded.decode(charset or "utf-8", errors="replace")
        except Exception:
            return decoded.decode("utf-8", errors="replace")
    return str(decoded)


def extract_body(msg: email.message.Message) -> tuple[str, str]:
    text = ""
    html = ""
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            cdisp = part.get("Content-Disposition", "")
            if "attachment" in cdisp:
                continue
            charset = part.get_content_charset() or "utf-8"
            payload = part.get_payload(decode=True)
            if payload is None:
                continue
            try:
                content = payload.decode(charset, errors="replace")
            except Exception:
                content = payload.decode("utf-8", errors="replace")
            if ctype == "text/plain" and not text:
                text = content
            elif ctype == "text/html" and not html:
                html = content
    else:
        charset = msg.get_content_charset() or "utf-8"
        payload = msg.get_payload(decode=True)
        if payload:
            try:
                content = payload.decode(charset, errors="replace")
            except Exception:
                content = payload.decode("utf-8", errors="replace")
            if msg.get_content_type() == "text/html":
                html = content
            else:
                text = content
    return text, html


def parse_inbound_event(payload: dict) -> dict:
    data = payload.get("data", {})
    email_id = data.get("email_id") or data.get("id")
    from_addr = data.get("from", "")
    sender_name, sender_email = parseaddr(from_addr)
    if not sender_email:
        sender_email = from_addr
    attachments = data.get("attachments", [])
    return {
        "resend_id": email_id,
        "direction": "inbound",
        "folder": "inbox",
        "sender_name": sender_name or None,
        "sender_email": sender_email or None,
        "recipient": ", ".join(data.get("to", [])) or None,
        "subject": data.get("subject", ""),
        "created_at": data.get("created_at") or now_iso(),
        "attachments": attachments,
    }


def is_spam(subject: str, body: str, sender_email: str) -> bool:
    text = f"{subject or ''} {body or ''} {sender_email or ''}".lower()
    score = 0
    for kw in SPAM_KEYWORDS:
        if kw in text:
            score += 1
    if sender_email and re.match(r'^[\w.-]+\+[\w.-]+@', sender_email):
        score += 1
    if sender_email and re.search(r'\d{4,}', sender_email):
        score += 1
    return score >= 2


def fetch_resend_email(email_id: str, api_key: str) -> dict:
    try:
        import resend
        return resend.Emails.Receiving.get(email_id=email_id) or {}
    except Exception as e:
        from flask import current_app
        current_app.logger.error(f"Failed to fetch email {email_id}: {e}")
        return {}


def download_attachments(attachments: list[dict], email_row_id: int) -> list[dict]:
    """Download attachments to disk and return metadata."""
    from openmail.config import ATTACHMENTS_DIR
    if not attachments:
        return []
    att_dir = ATTACHMENTS_DIR / str(email_row_id)
    att_dir.mkdir(parents=True, exist_ok=True)
    saved = []
    for att in attachments:
        filename = att.get("filename", "attachment.bin")
        content_type = att.get("content_type", "application/octet-stream")
        url = att.get("url")
        if url:
            try:
                r = requests.get(url, timeout=30)
                if r.status_code == 200:
                    (att_dir / filename).write_bytes(r.content)
                    saved.append({"filename": filename, "content_type": content_type})
            except Exception:
                pass
    return saved
