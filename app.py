import os
import sqlite3
import ssl
import email
import imaplib
import json
import queue
from datetime import datetime, timezone
from email.header import decode_header
from email.mime.text import MIMEText
from email.utils import parseaddr
from pathlib import Path
from typing import Any

import resend
import requests
from dotenv import load_dotenv
from flask import Flask, Response, abort, jsonify, render_template, request, stream_with_context

load_dotenv()

app = Flask(__name__)
DB_PATH = Path("emails.db")

# Resend configuration
RESEND_API_KEY = os.environ.get("RESEND_API_KEY")
RESEND_DOMAIN = os.environ.get("RESEND_DOMAIN", "adamec.pro")
RESEND_WEBHOOK_SECRET = os.environ.get("RESEND_WEBHOOK_SECRET")
FROM_EMAIL = os.environ.get("FROM_EMAIL", f"dominik@{RESEND_DOMAIN}")
FROM_NAME = os.environ.get("FROM_NAME", "Dominik Adamec")

if RESEND_API_KEY:
    resend.api_key = RESEND_API_KEY

# SSE: one queue per connected client
_sse_clients: list[queue.Queue] = []


def notify_sse(event: str, data: dict):
    """Push event to all connected SSE clients."""
    payload = json.dumps(data)
    dead: list[queue.Queue] = []
    for q in _sse_clients:
        try:
            q.put_nowait((event, payload))
        except queue.Full:
            dead.append(q)
    for q in dead:
        _sse_clients.remove(q)


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS emails (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resend_id TEXT UNIQUE,
            direction TEXT NOT NULL CHECK(direction IN ('inbound','outbound')),
            folder TEXT DEFAULT 'inbox',
            sender_name TEXT,
            sender_email TEXT,
            recipient TEXT,
            subject TEXT,
            body_text TEXT,
            body_html TEXT,
            headers TEXT,
            attachments TEXT,
            raw_url TEXT,
            is_starred INTEGER DEFAULT 0,
            is_read INTEGER DEFAULT 0,
            created_at TEXT,
            received_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_emails_direction ON emails(direction);
        CREATE INDEX IF NOT EXISTS idx_emails_folder ON emails(folder);
        CREATE INDEX IF NOT EXISTS idx_emails_starred ON emails(is_starred);
        CREATE INDEX IF NOT EXISTS idx_emails_created ON emails(created_at DESC);
        """
    )
    conn.commit()
    conn.close()


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def now_iso():
    return datetime.now(timezone.utc).isoformat()


def decode_value(value):
    if value is None:
        return ""
    decoded, charset = decode_header(value)[0]
    if isinstance(decoded, bytes):
        try:
            return decoded.decode(charset or "utf-8", errors="replace")
        except Exception:
            return decoded.decode("utf-8", errors="replace")
    return str(decoded)


def extract_body(msg: email.message.Message):
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
    return {
        "resend_id": email_id,
        "direction": "inbound",
        "folder": "inbox",
        "sender_name": sender_name or None,
        "sender_email": sender_email or None,
        "recipient": ", ".join(data.get("to", [])) or None,
        "subject": data.get("subject", ""),
        "created_at": data.get("created_at") or now_iso(),
        "headers": None,
        "attachments": None,
    }


def fetch_resend_email(email_id: str) -> dict:
    """Fetch full email content from Resend receiving API."""
    if not RESEND_API_KEY:
        raise RuntimeError("RESEND_API_KEY not configured")
    try:
        email_data = resend.Emails.Receiving.get(email_id=email_id)
        return email_data
    except Exception as e:
        app.logger.error(f"Failed to fetch email {email_id}: {e}")
        return {}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html", from_email=FROM_EMAIL)


@app.route("/api/events")
def sse_stream():
    """Server-Sent Events stream for real-time notifications."""
    q: queue.Queue = queue.Queue(maxsize=100)
    _sse_clients.append(q)

    def generate():
        try:
            # Send initial keepalive
            yield "event: connected\ndata: {}\n\n"
            while True:
                try:
                    event, data = q.get(timeout=30)
                    yield f"event: {event}\ndata: {data}\n\n"
                except queue.Empty:
                    yield ": keepalive\n\n"
        except GeneratorExit:
            pass
        finally:
            if q in _sse_clients:
                _sse_clients.remove(q)

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.route("/api/emails", methods=["GET"])
def list_emails():
    folder = request.args.get("folder", "inbox")
    direction = request.args.get("direction", "inbound")
    starred = request.args.get("starred", type=int)
    limit = request.args.get("limit", 50, type=int)
    offset = request.args.get("offset", 0, type=int)

    conn = get_db()
    params: list[Any] = []
    where = ["direction = ?"]
    params.append(direction)

    if folder:
        where.append("folder = ?")
        params.append(folder)
    if starred is not None:
        where.append("is_starred = ?")
        params.append(starred)

    sql = "SELECT id, folder, sender_name, sender_email, recipient, subject, substr(body_text, 1, 300) as preview, is_starred, is_read, created_at FROM emails WHERE " + " AND ".join(where) + " ORDER BY datetime(created_at) DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    rows = conn.execute(sql, params).fetchall()
    conn.close()
    return jsonify([dict(row) for row in rows])


@app.route("/api/emails/<int:email_id>", methods=["GET"])
def get_email(email_id):
    conn = get_db()
    row = conn.execute("SELECT * FROM emails WHERE id = ?", (email_id,)).fetchone()
    if row:
        conn.execute("UPDATE emails SET is_read = 1 WHERE id = ?", (email_id,))
        conn.commit()
    conn.close()
    if row is None:
        return jsonify({"error": "Email not found"}), 404
    return jsonify(dict(row))


@app.route("/api/emails/<int:email_id>", methods=["DELETE"])
def delete_email(email_id):
    conn = get_db()
    conn.execute("DELETE FROM emails WHERE id = ?", (email_id,))
    conn.commit()
    conn.close()
    return jsonify({"deleted": True})


@app.route("/api/emails/<int:email_id>", methods=["PATCH"])
def update_email(email_id):
    data = request.json or {}
    allowed = {"is_starred", "is_read", "folder"}
    fields = {k: v for k, v in data.items() if k in allowed}
    if not fields:
        return jsonify({"error": "No valid fields"}), 400

    conn = get_db()
    set_clause = ", ".join(f"{k} = ?" for k in fields)
    values = list(fields.values()) + [email_id]
    conn.execute(f"UPDATE emails SET {set_clause} WHERE id = ?", values)
    conn.commit()
    row = conn.execute("SELECT * FROM emails WHERE id = ?", (email_id,)).fetchone()
    conn.close()
    return jsonify(dict(row))


@app.route("/api/send", methods=["POST"])
def send_email():
    if not RESEND_API_KEY:
        return jsonify({"error": "RESEND_API_KEY not configured"}), 400

    data = request.json or {}
    to = data.get("to", "").strip()
    subject = data.get("subject", "").strip()
    body = data.get("body", "")

    if not to or not subject:
        return jsonify({"error": "Missing recipient or subject"}), 400

    try:
        from_header = FROM_EMAIL
        if FROM_NAME:
            from_header = f"{FROM_NAME} <{FROM_EMAIL}>"

        params: resend.Emails.SendParams = {
            "from": from_header,
            "to": [to],
            "subject": subject,
            "text": body,
            "reply_to": FROM_EMAIL,
        }
        result = resend.Emails.send(params)

        # Store outbound email locally
        conn = get_db()
        conn.execute(
            """
            INSERT INTO emails
            (resend_id, direction, folder, sender_name, sender_email, recipient,
             subject, body_text, body_html, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                result.get("id"),
                "outbound",
                "sent",
                FROM_NAME,
                FROM_EMAIL,
                to,
                subject,
                body,
                None,
                now_iso(),
            ),
        )
        conn.commit()
        conn.close()

        return jsonify({"status": "sent", "provider": "resend", "id": result.get("id")})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/inbound", methods=["POST"])
def inbound_webhook():
    """Receive inbound email webhook from Resend."""
    payload = request.get_json(silent=True) or {}
    if payload.get("type") != "email.received":
        return jsonify({"ok": True})

    parsed = parse_inbound_event(payload)
    email_id = parsed["resend_id"]
    if not email_id:
        return jsonify({"error": "Missing email id"}), 400

    # Avoid duplicates
    conn = get_db()
    existing = conn.execute(
        "SELECT id FROM emails WHERE resend_id = ?", (email_id,)
    ).fetchone()
    if existing:
        conn.close()
        return jsonify({"ok": True, "id": existing["id"], "new": False})

    # Fetch full email content
    full_email = fetch_resend_email(email_id)
    body_text = full_email.get("text") if full_email else ""
    body_html = full_email.get("html") if full_email else ""
    headers = None
    attachments = None
    raw_url = None
    if full_email:
        headers = str(full_email.get("headers")) if full_email.get("headers") else None
        attachments = str(full_email.get("attachments")) if full_email.get("attachments") else None
        raw = full_email.get("raw") or {}
        raw_url = raw.get("download_url")
        if not body_text and not body_html:
            body_text = full_email.get("subject", "")

    conn.execute(
        """
        INSERT INTO emails
        (resend_id, direction, folder, sender_name, sender_email, recipient,
         subject, body_text, body_html, headers, attachments, raw_url, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            parsed["resend_id"],
            parsed["direction"],
            parsed["folder"],
            parsed["sender_name"],
            parsed["sender_email"],
            parsed["recipient"],
            parsed["subject"],
            body_text or None,
            body_html or None,
            headers,
            attachments,
            raw_url,
            parsed["created_at"],
        ),
    )
    email_row_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    conn.commit()
    conn.close()

    # Notify SSE clients
    notify_sse("new_email", {"id": email_row_id, "subject": parsed["subject"]})

    return jsonify({"ok": True, "id": email_row_id, "new": True})


@app.route("/api/folders", methods=["GET"])
def list_folders():
    return jsonify(["inbox", "sent", "starred"])


@app.route("/api/stats", methods=["GET"])
def stats():
    conn = get_db()
    inbound = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE direction = 'inbound'"
    ).fetchone()[0]
    outbound = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE direction = 'outbound'"
    ).fetchone()[0]
    starred = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE is_starred = 1"
    ).fetchone()[0]
    unread = conn.execute(
        "SELECT COUNT(*) FROM emails WHERE direction = 'inbound' AND is_read = 0"
    ).fetchone()[0]
    conn.close()
    return jsonify({"inbound": inbound, "outbound": outbound, "starred": starred, "unread": unread})


# ---------------------------------------------------------------------------
# Manual sync from Resend receiving API
# ---------------------------------------------------------------------------
@app.route("/api/sync", methods=["POST"])
def sync_emails():
    if not RESEND_API_KEY:
        return jsonify({"error": "RESEND_API_KEY not configured"}), 400
    try:
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
        for item in data:
            email_id = item.get("id")
            if not email_id:
                continue
            conn = get_db()
            existing = conn.execute(
                "SELECT id FROM emails WHERE resend_id = ?", (email_id,)
            ).fetchone()
            conn.close()
            if existing:
                continue
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
            with app.test_client() as client:
                client.post(
                    "/api/inbound",
                    json=webhook_payload,
                    headers={"Content-Type": "application/json"},
                )
            imported += 1
        return jsonify({"imported": imported})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    init_db()
    app.run(
        host=os.environ.get("FLASK_HOST", "127.0.0.1"),
        port=int(os.environ.get("FLASK_PORT", 5005)),
        debug=os.environ.get("FLASK_DEBUG", "false").lower() == "true",
    )
