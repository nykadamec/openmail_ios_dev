import os
import base64
import sqlite3
import ssl
import email
import imaplib
import json
import queue
import secrets
import re
from datetime import datetime, timezone, timedelta
from email.header import decode_header
from email.mime.text import MIMEText
from email.utils import parseaddr
from pathlib import Path
from typing import Any, Optional

import resend
import requests
import bcrypt
import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from dotenv import load_dotenv
from flask import (
    Flask, Response, abort, jsonify, make_response,
    render_template, request, stream_with_context, redirect, url_for
)

load_dotenv()

# ---------------------------------------------------------------------------
# Password-derived encryption for stored emails
# ---------------------------------------------------------------------------
# Each user has a random Data Encryption Key (DEK). The DEK is encrypted by a
# key derived from the user's password (PBKDF2) and stored in the DB. After
# login the decrypted DEK lives only in server memory (USER_DEKS). When the
# server restarts, users must log in again to unlock their data.
USER_DEKS: dict[int, bytes] = {}


def _derive_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=600_000,
    )
    return kdf.derive(password.encode('utf-8'))


def _encrypt_dek(dek: bytes, password: str, salt: bytes) -> str:
    key = _derive_key(password, salt)
    aes = AESGCM(key)
    nonce = secrets.token_bytes(12)
    ct = aes.encrypt(nonce, dek, None)
    return base64.urlsafe_b64encode(nonce + ct).decode().rstrip('=')


def _decrypt_dek(ciphertext: str, password: str, salt: bytes) -> bytes:
    key = _derive_key(password, salt)
    aes = AESGCM(key)
    pad = 4 - (len(ciphertext) % 4)
    if pad != 4:
        ciphertext += '=' * pad
    data = base64.urlsafe_b64decode(ciphertext.encode())
    nonce = data[:12]
    ct = data[12:]
    return aes.decrypt(nonce, ct, None)


def _get_user_dek(user_id: int) -> bytes | None:
    return USER_DEKS.get(user_id)


def _set_user_dek(user_id: int, dek: bytes):
    USER_DEKS[user_id] = dek


def _clear_user_dek(user_id: int):
    USER_DEKS.pop(user_id, None)


def encrypt_email_field(value: str | None, user_id: int | None = None) -> str | None:
    if value is None:
        return None
    dek = _get_user_dek(user_id) if user_id else None
    if dek is None:
        raise RuntimeError('Encryption key not available. User must log in.')
    aes = AESGCM(dek)
    nonce = secrets.token_bytes(12)
    ct = aes.encrypt(nonce, value.encode('utf-8'), None)
    return base64.urlsafe_b64encode(nonce + ct).decode().rstrip('=')


def _current_user_id() -> Optional[int]:
    """Return current user id from session or CF Access. Does not create response side effects."""
    user = current_user()
    if user:
        return user['id']
    if CF_ACCESS_ENABLED:
        user_id = _auto_login_from_cf_access()
        if user_id:
            return user_id
    return None

def decrypt_email_field(token: str | None, user_id: int | None = None) -> str | None:
    if token is None:
        return None
    dek = _get_user_dek(user_id) if user_id else None
    if dek is None:
        return token
    aes = AESGCM(dek)
    try:
        pad = 4 - (len(token) % 4)
        if pad != 4:
            token += '=' * pad
        data = base64.urlsafe_b64decode(token.encode())
        nonce = data[:12]
        ct = data[12:]
        return aes.decrypt(nonce, ct, None).decode('utf-8')
    except Exception:
        return token


app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(32))
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(minutes=15)
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
# Cloudflare Access (Zero Trust) integration
# ---------------------------------------------------------------------------
CF_ACCESS_ENABLED = os.environ.get('CLOUDFLARE_ACCESS_ENABLED', 'false').lower() == 'true'
CF_TEAM_DOMAIN = os.environ.get('CLOUDFLARE_TEAM_DOMAIN', '')
CF_AUD_TAG = os.environ.get('CLOUDFLARE_AUD_TAG', '')
_CF_ACCESS_PUBLIC_KEYS: list = []
_CF_ACCESS_KEYS_LOADED_AT: Optional[datetime] = None


def _load_cf_access_keys():
    global _CF_ACCESS_PUBLIC_KEYS, _CF_ACCESS_KEYS_LOADED_AT
    if not CF_TEAM_DOMAIN:
        return
    now = datetime.now(timezone.utc)
    if _CF_ACCESS_KEYS_LOADED_AT and (now - _CF_ACCESS_KEYS_LOADED_AT) < timedelta(hours=1):
        return
    try:
        url = f'https://{CF_TEAM_DOMAIN}/cdn-cgi/access/certs'
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        certs = r.json()
        keys = []
        for cert in certs.get('keys', []):
            try:
                key = serialization.load_pem_public_key(cert['public_key'].encode())
                keys.append(key)
            except Exception:
                continue
        _CF_ACCESS_PUBLIC_KEYS = keys
        _CF_ACCESS_KEYS_LOADED_AT = now
    except Exception:
        _CF_ACCESS_PUBLIC_KEYS = []


def _verify_cf_access_token(token: str) -> Optional[dict]:
    """Verify Cloudflare Access JWT. Returns payload or None."""
    if not token or not CF_TEAM_DOMAIN or not CF_AUD_TAG:
        return None
    _load_cf_access_keys()
    for key in _CF_ACCESS_PUBLIC_KEYS:
        try:
            payload = jwt.decode(
                token,
                key,
                algorithms=['RS256'],
                audience=CF_AUD_TAG,
                options={'require': ['exp', 'iat', 'sub', 'aud']},
            )
            return payload
        except jwt.InvalidTokenError:
            continue
    return None


def _get_cf_access_email() -> Optional[str]:
    token = request.headers.get('Cf-Access-Jwt-Assertion')
    if not token:
        return None
    payload = _verify_cf_access_token(token)
    if not payload:
        return None
    # Cloudflare Access puts user email in 'email' claim
    return payload.get('email') or payload.get('sub')


def _auto_login_from_cf_access() -> Optional[int]:
    if not CF_ACCESS_ENABLED:
        return None
    email = _get_cf_access_email()
    if not email:
        return None
    username = email.split('@')[0].lower()
    conn = get_db()
    row = conn.execute('SELECT id FROM users WHERE username = ?', (username,)).fetchone()
    if not row:
        # Auto-provision a local user for this Cloudflare-authenticated email
        temp_pw = bcrypt.hashpw(secrets.token_hex(32).encode(), bcrypt.gensalt(rounds=12)).decode()
        c = conn.execute('INSERT INTO users (username, password_hash) VALUES (?, ?)', (username, temp_pw))
        user_id = c.lastrowid
        conn.commit()
    else:
        user_id = row['id']
    conn.close()
    return user_id


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            dek_salt TEXT,
            encrypted_dek TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            user_id INTEGER NOT NULL,
            last_seen TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS emails (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resend_id TEXT UNIQUE,
            direction TEXT NOT NULL CHECK(direction IN ('inbound','outbound')),
            folder TEXT DEFAULT 'inbox',
            custom_folder_id INTEGER,
            sender_name TEXT,
            sender_email TEXT,
            recipient TEXT,
            subject TEXT,
            preview TEXT,
            body_text TEXT,
            body_html TEXT,
            headers TEXT,
            attachments TEXT,
            raw_url TEXT,
            is_starred INTEGER DEFAULT 0,
            is_read INTEGER DEFAULT 0,
            is_spam INTEGER DEFAULT 0,
            is_trash INTEGER DEFAULT 0,
            created_at TEXT,
            received_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_emails_direction ON emails(direction);
        CREATE INDEX IF NOT EXISTS idx_emails_folder ON emails(folder);
        CREATE INDEX IF NOT EXISTS idx_emails_starred ON emails(is_starred);
        CREATE INDEX IF NOT EXISTS idx_emails_spam ON emails(is_spam);
        CREATE INDEX IF NOT EXISTS idx_emails_trash ON emails(is_trash);
        CREATE INDEX IF NOT EXISTS idx_emails_created ON emails(created_at DESC);

        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            notes TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, email),
            FOREIGN KEY(user_id) REFERENCES users(id)
        );
        CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id);

        CREATE TABLE IF NOT EXISTS custom_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            color TEXT DEFAULT '#ff6b35',
            icon TEXT DEFAULT '📁',
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY(user_id) REFERENCES users(id)
        );
        """
    )
    conn.commit()
    count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    conn.close()
    if count == 0:
        default_pw = os.environ.get("DEFAULT_USER_PASSWORD", "adamec")
        create_user("dominik", default_pw)
        print("=" * 60)
        print(f"Vytvořen výchozí uživatel: dominik / {default_pw}")
        print("Změň heslo v Nastavení po přihlášení.")
        print("=" * 60)


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------
SESSION_TIMEOUT = timedelta(minutes=15)


def has_users() -> bool:
    conn = get_db()
    row = conn.execute("SELECT COUNT(*) as c FROM users").fetchone()
    conn.close()
    return row['c'] > 0


def create_user(username: str, password: str) -> int:
    """Create a new user and return the user id. Generates a random DEK encrypted by password."""
    pw_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())
    dek = AESGCM.generate_key(bit_length=256)
    salt = secrets.token_bytes(16)
    encrypted_dek = _encrypt_dek(dek, password, salt)
    conn = get_db()
    cur = conn.execute(
        "INSERT INTO users (username, password_hash, dek_salt, encrypted_dek) VALUES (?, ?, ?, ?)",
        (username, pw_hash.decode('utf-8'), base64.urlsafe_b64encode(salt).decode(), encrypted_dek)
    )
    conn.commit()
    user_id = cur.lastrowid
    conn.close()
    _set_user_dek(user_id, dek)
    return user_id


def verify_user(username: str, password: str) -> Optional[int]:
    """Verify username/password, decrypt DEK into memory, and return user_id or None."""
    conn = get_db()
    row = conn.execute(
        "SELECT id, password_hash, dek_salt, encrypted_dek FROM users WHERE username = ?",
        (username,)
    ).fetchone()
    conn.close()
    if not row:
        return None
    if bcrypt.checkpw(password.encode('utf-8'), row['password_hash'].encode('utf-8')):
        user_id = row['id']
        try:
            salt = base64.urlsafe_b64decode(row['dek_salt'].encode())
            dek = _decrypt_dek(row['encrypted_dek'], password, salt)
            _set_user_dek(user_id, dek)
        except Exception as e:
            app.logger.error(f'Failed to decrypt DEK for user {user_id}: {e}')
            return None
        return user_id
    return None


def create_session(user_id: int) -> str:
    """Create a new session and return the session id."""
    sid = secrets.token_urlsafe(32)
    conn = get_db()
    conn.execute(
        "INSERT INTO sessions (id, user_id, last_seen) VALUES (?, ?, ?)",
        (sid, user_id, datetime.now(timezone.utc).isoformat())
    )
    conn.commit()
    conn.close()
    return sid


def get_session(sid: str) -> Optional[dict]:
    """Get session if not expired. Refresh last_seen on success."""
    if not sid:
        return None
    conn = get_db()
    row = conn.execute(
        "SELECT id, user_id, last_seen FROM sessions WHERE id = ?",
        (sid,)
    ).fetchone()
    if not row:
        conn.close()
        return None
    last_seen = datetime.fromisoformat(row['last_seen'])
    if datetime.now(timezone.utc) - last_seen > SESSION_TIMEOUT:
        conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
        conn.commit()
        conn.close()
        return None
    # Refresh last_seen
    conn.execute(
        "UPDATE sessions SET last_seen = ? WHERE id = ?",
        (datetime.now(timezone.utc).isoformat(), sid)
    )
    conn.commit()
    conn.close()
    return {'id': row['id'], 'user_id': row['user_id']}


def delete_session(sid: str):
    conn = get_db()
    conn.execute("DELETE FROM sessions WHERE id = ?", (sid,))
    conn.commit()
    conn.close()


def current_user() -> Optional[dict]:
    """Return current authenticated user or None.

    If Cloudflare Access is enabled and a valid token is present,
    auto-provision/login the user and return them."""
    sid = request.cookies.get('session_id')
    session = get_session(sid)
    if session:
        conn = get_db()
        row = conn.execute(
            "SELECT id, username FROM users WHERE id = ?",
            (session['user_id'],)
        ).fetchone()
        conn.close()
        if row:
            return dict(row)
    # Try Cloudflare Access automatic login if configured
    if CF_ACCESS_ENABLED:
        user_id = _auto_login_from_cf_access()
        if user_id:
            new_sid = create_session(user_id)
            # Store the new session id on the request for response setup later
            request._cf_session_id = new_sid
            conn = get_db()
            row = conn.execute("SELECT id, username FROM users WHERE id = ?", (user_id,)).fetchone()
            conn.close()
            return dict(row) if row else None
    return None


def login_required(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*args, **kwargs):
        user = current_user()
        if not user:
            if request.path.startswith('/api/'):
                return jsonify({'error': 'Unauthorized'}), 401
            return redirect(url_for('login_page'))
        return f(*args, **kwargs)
    return wrapped


# ---------------------------------------------------------------------------
# Spam classifier (simple keyword-based)
# ---------------------------------------------------------------------------
SPAM_KEYWORDS = [
    'viagra', 'cialis', 'lottery', 'winner', 'click here', 'free money',
    'make money fast', 'nigerian prince', 'bitcoin investment', 'crypto giveaway',
    'weight loss', 'miracle', 'limited time offer', 'act now',
    'congratulations you', 'you have been selected', 'claim your prize',
    'suspend your account', 'verify your password immediately',
]


def is_spam(subject: str, body: str, sender_email: str) -> bool:
    """Simple heuristic spam detection."""
    text = f"{subject or ''} {body or ''} {sender_email or ''}".lower()
    score = 0
    for kw in SPAM_KEYWORDS:
        if kw in text:
            score += 1
    # Suspicious sender patterns
    if sender_email and re.match(r'^[\w.-]+\+[\w.-]+@', sender_email):
        score += 1
    if sender_email and re.search(r'\d{4,}', sender_email):
        score += 1
    return score >= 2


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
    }


def fetch_resend_email(email_id: str) -> dict:
    if not RESEND_API_KEY:
        raise RuntimeError("RESEND_API_KEY not configured")
    try:
        return resend.Emails.Receiving.get(email_id=email_id) or {}
    except Exception as e:
        app.logger.error(f"Failed to fetch email {email_id}: {e}")
        return {}


# ---------------------------------------------------------------------------
# Public routes
# ---------------------------------------------------------------------------
@app.route("/setup", methods=["GET", "POST"])
def setup():
    if has_users():
        return redirect(url_for('login_page'))
    if request.method == "POST":
        data = request.form if request.form else (request.json or {})
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""
        if not username or len(password) < 6:
            return render_template("setup.html", error="Heslo musí mít alespoň 6 znaků"), 400
        user_id = create_user(username, password)
        sid = create_session(user_id)
        resp = make_response(redirect(url_for('index')))
        resp.set_cookie('session_id', sid, httponly=True, samesite='Lax', max_age=15*60)
        return resp
    return render_template("setup.html")


@app.route("/login", methods=["GET", "POST"])
def login_page():
    user = current_user()
    if user:
        resp = make_response(redirect(url_for('index')))
        if hasattr(request, '_cf_session_id'):
            resp.set_cookie('session_id', request._cf_session_id, httponly=True, samesite='Lax', max_age=15*60)
        return resp
    if CF_ACCESS_ENABLED:
        # If CF Access is enabled but token missing/invalid, let Cloudflare redirect to its login
        return render_template("login.html", error="Přístup vyžaduje Cloudflare Access autentizaci."), 403
    if request.method == "POST":
        data = request.form if request.form else (request.json or {})
        username = (data.get("username") or "").strip()
        password = data.get("password") or ""
        user_id = verify_user(username, password)
        if not user_id:
            return render_template("login.html", error="Neplatné přihlašovací údaje"), 401
        sid = create_session(user_id)
        resp = make_response(redirect(url_for('index')))
        resp.set_cookie('session_id', sid, httponly=True, samesite='Lax', max_age=15*60)
        return resp
    return render_template("login.html")


@app.route("/logout", methods=["POST", "GET"])
def logout():
    sid = request.cookies.get('session_id')
    if sid:
        session = get_session(sid)
        if session:
            _clear_user_dek(session['user_id'])
        delete_session(sid)
    resp = make_response(redirect(url_for('login_page')))
    resp.delete_cookie('session_id')
    return resp


@app.route("/")
@login_required
def index():
    resp = make_response(render_template("index.html", from_email=FROM_EMAIL))
    if hasattr(request, '_cf_session_id'):
        resp.set_cookie('session_id', request._cf_session_id, httponly=True, samesite='Lax', max_age=15*60)
    return resp


# ---------------------------------------------------------------------------
# API routes
# ---------------------------------------------------------------------------
@app.route("/api/me")
def me():
    user = current_user()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(user)


@app.route("/api/events")
@login_required
def sse_stream():
    q: queue.Queue = queue.Queue(maxsize=100)
    _sse_clients.append(q)

    def generate():
        try:
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
@login_required
def list_emails():
    folder = request.args.get("folder", "inbox")
    direction = request.args.get("direction", "inbound")
    starred = request.args.get("starred", type=int)
    limit = request.args.get("limit", 50, type=int)
    offset = request.args.get("offset", 0, type=int)
    is_spam = request.args.get("is_spam", type=int)
    is_trash = request.args.get("is_trash", type=int)
    custom_folder_id = request.args.get("custom_folder_id", type=int)

    conn = get_db()
    params: list[Any] = []
    where = ["direction = ?"]
    params.append(direction)

    if folder and not custom_folder_id:
        where.append("folder = ?")
        params.append(folder)
    if starred is not None:
        where.append("is_starred = ?")
        params.append(starred)
    if is_spam is not None:
        where.append("is_spam = ?")
        params.append(is_spam)
    if is_trash is not None:
        where.append("is_trash = ?")
        params.append(is_trash)
    if custom_folder_id:
        where.append("custom_folder_id = ?")
        params.append(custom_folder_id)

    sql = "SELECT id, folder, custom_folder_id, sender_name, sender_email, recipient, subject, preview, is_starred, is_read, is_spam, is_trash, created_at FROM emails WHERE " + " AND ".join(where) + " ORDER BY datetime(created_at) DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    user_id = _current_user_id()
    result = []
    for row in rows:
        d = dict(row)
        d['sender_name'] = decrypt_email_field(d.get('sender_name'), user_id)
        d['sender_email'] = decrypt_email_field(d.get('sender_email'), user_id)
        d['recipient'] = decrypt_email_field(d.get('recipient'), user_id)
        d['subject'] = decrypt_email_field(d.get('subject'), user_id)
        d['preview'] = decrypt_email_field(d.get('preview'), user_id)
        result.append(d)
    return jsonify(result)


@app.route("/api/emails/<int:email_id>", methods=["GET"])
@login_required
def get_email(email_id):
    conn = get_db()
    row = conn.execute("SELECT * FROM emails WHERE id = ?", (email_id,)).fetchone()
    if row:
        conn.execute("UPDATE emails SET is_read = 1 WHERE id = ?", (email_id,))
        conn.commit()
    conn.close()
    if row is None:
        return jsonify({"error": "Email not found"}), 404
    user_id = _current_user_id()
    d = dict(row)
    d['sender_name'] = decrypt_email_field(d.get('sender_name'), user_id)
    d['sender_email'] = decrypt_email_field(d.get('sender_email'), user_id)
    d['recipient'] = decrypt_email_field(d.get('recipient'), user_id)
    d['subject'] = decrypt_email_field(d.get('subject'), user_id)
    d['preview'] = decrypt_email_field(d.get('preview'), user_id)
    d['body_text'] = decrypt_email_field(d.get('body_text'), user_id)
    d['body_html'] = decrypt_email_field(d.get('body_html'), user_id)
    return jsonify(d)


@app.route("/api/emails/<int:email_id>", methods=["DELETE"])
@login_required
def delete_email(email_id):
    conn = get_db()
    conn.execute("UPDATE emails SET is_trash = 1 WHERE id = ?", (email_id,))
    conn.commit()
    conn.close()
    return jsonify({"deleted": True})


@app.route("/api/emails/<int:email_id>", methods=["PATCH"])
@login_required
def update_email(email_id):
    data = request.json or {}
    allowed = {"is_starred", "is_read", "folder", "is_spam", "is_trash", "custom_folder_id"}
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
@login_required
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
        from_header = FROM_EMAIL if not FROM_NAME else f"{FROM_NAME} <{FROM_EMAIL}>"
        params: resend.Emails.SendParams = {
            "from": from_header,
            "to": [to],
            "subject": subject,
            "text": body,
            "reply_to": FROM_EMAIL,
        }
        result = resend.Emails.send(params)
        conn = get_db()
        user_id = _current_user_id() or 1
        preview = (body or "")[:300]
        conn.execute(
            """INSERT INTO emails
            (resend_id, direction, folder, sender_name, sender_email, recipient,
             subject, preview, body_text, body_html, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                result.get("id"),
                "outbound",
                "sent",
                encrypt_email_field(FROM_NAME, user_id),
                encrypt_email_field(FROM_EMAIL, user_id),
                encrypt_email_field(to, user_id),
                encrypt_email_field(subject, user_id),
                encrypt_email_field(preview, user_id),
                encrypt_email_field(body, user_id),
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
    """Receive inbound email webhook from Resend. No auth required (Resend signature)."""
    payload = request.get_json(silent=True) or {}
    if payload.get("type") != "email.received":
        return jsonify({"ok": True})
    parsed = parse_inbound_event(payload)
    email_id = parsed["resend_id"]
    if not email_id:
        return jsonify({"error": "Missing email id"}), 400

    conn = get_db()
    existing = conn.execute(
        "SELECT id FROM emails WHERE resend_id = ?", (email_id,)
    ).fetchone()
    if existing:
        conn.close()
        return jsonify({"ok": True, "id": existing["id"], "new": False})

    full_email = fetch_resend_email(email_id)
    body_text = full_email.get("text") if full_email else ""
    body_html = full_email.get("html") if full_email else ""
    if not body_text and not body_html:
        body_text = full_email.get("subject", "")

    # Spam classification
    spam = is_spam(parsed["subject"], body_text, parsed["sender_email"] or "")
    folder = "spam" if spam else "inbox"

    user_id = _current_user_id() or 1
    preview = (body_text or "")[:300]
    conn.execute(
        """INSERT INTO emails
        (resend_id, direction, folder, sender_name, sender_email, recipient,
         subject, preview, body_text, body_html, is_spam, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            parsed["resend_id"],
            parsed["direction"],
            folder,
            encrypt_email_field(parsed["sender_name"], user_id),
            encrypt_email_field(parsed["sender_email"], user_id),
            encrypt_email_field(parsed["recipient"], user_id),
            encrypt_email_field(parsed["subject"], user_id),
            encrypt_email_field(preview, user_id),
            encrypt_email_field(body_text or None, user_id),
            encrypt_email_field(body_html or None, user_id),
            1 if spam else 0,
            parsed["created_at"],
        ),
    )
    email_row_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    conn.commit()
    conn.close()

    notify_sse("new_email", {
        "id": email_row_id, "subject": parsed["subject"], "is_spam": spam
    })
    return jsonify({"ok": True, "id": email_row_id, "new": True, "is_spam": spam})


@app.route("/api/folders", methods=["GET"])
@login_required
def list_folders():
    user = current_user()
    conn = get_db()
    custom = conn.execute(
        "SELECT id, name, color, icon FROM custom_folders WHERE user_id = ? ORDER BY name",
        (user['id'],)
    ).fetchall()
    conn.close()
    return jsonify({
        "system": ["inbox", "sent", "starred", "spam", "trash"],
        "custom": [dict(r) for r in custom]
    })


@app.route("/api/custom_folders", methods=["POST"])
@login_required
def create_custom_folder():
    user = current_user()
    data = request.json or {}
    name = (data.get("name") or "").strip()
    color = data.get("color", "#ff6b35")
    icon = data.get("icon", "📁")
    if not name:
        return jsonify({"error": "Name required"}), 400
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO custom_folders (user_id, name, color, icon) VALUES (?, ?, ?, ?)",
            (user['id'], name, color, icon)
        )
        conn.commit()
        folder_id = cur.lastrowid
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({"error": "Folder already exists"}), 400
    conn.close()
    return jsonify({"id": folder_id, "name": name, "color": color, "icon": icon})


@app.route("/api/custom_folders/<int:folder_id>", methods=["DELETE"])
@login_required
def delete_custom_folder(folder_id):
    user = current_user()
    conn = get_db()
    conn.execute("DELETE FROM custom_folders WHERE id = ? AND user_id = ?", (folder_id, user['id']))
    # Move emails in this folder back to inbox
    conn.execute("UPDATE emails SET custom_folder_id = NULL WHERE custom_folder_id = ?", (folder_id,))
    conn.commit()
    conn.close()
    return jsonify({"deleted": True})


@app.route("/api/stats", methods=["GET"])
@login_required
def stats():
    conn = get_db()
    inbound = conn.execute("SELECT COUNT(*) FROM emails WHERE direction = 'inbound' AND is_trash = 0").fetchone()[0]
    outbound = conn.execute("SELECT COUNT(*) FROM emails WHERE direction = 'outbound' AND is_trash = 0").fetchone()[0]
    starred = conn.execute("SELECT COUNT(*) FROM emails WHERE is_starred = 1 AND is_trash = 0").fetchone()[0]
    unread = conn.execute("SELECT COUNT(*) FROM emails WHERE direction = 'inbound' AND is_read = 0 AND is_trash = 0").fetchone()[0]
    spam = conn.execute("SELECT COUNT(*) FROM emails WHERE is_spam = 1 AND is_trash = 0").fetchone()[0]
    trash = conn.execute("SELECT COUNT(*) FROM emails WHERE is_trash = 1").fetchone()[0]
    conn.close()
    return jsonify({
        "inbound": inbound, "outbound": outbound, "starred": starred,
        "unread": unread, "spam": spam, "trash": trash
    })


# ---------------------------------------------------------------------------
# Contacts API
# ---------------------------------------------------------------------------
@app.route("/api/contacts", methods=["GET"])
@login_required
def list_contacts():
    user = current_user()
    q = (request.args.get("q") or "").lower()
    conn = get_db()
    if q:
        rows = conn.execute(
            """SELECT id, name, email, notes FROM contacts
            WHERE user_id = ? AND (LOWER(name) LIKE ? OR LOWER(email) LIKE ?)
            ORDER BY name LIMIT 20""",
            (user['id'], f"%{q}%", f"%{q}%")
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT id, name, email, notes FROM contacts WHERE user_id = ? ORDER BY name",
            (user['id'],)
        ).fetchall()
    conn.close()
    return jsonify([dict(r) for r in rows])


@app.route("/api/contacts", methods=["POST"])
@login_required
def create_contact():
    user = current_user()
    data = request.json or {}
    name = (data.get("name") or "").strip()
    email_addr = (data.get("email") or "").strip().lower()
    notes = data.get("notes")
    if not name or not email_addr:
        return jsonify({"error": "Name and email required"}), 400
    conn = get_db()
    try:
        cur = conn.execute(
            "INSERT INTO contacts (user_id, name, email, notes) VALUES (?, ?, ?, ?)",
            (user['id'], name, email_addr, notes)
        )
        conn.commit()
        contact_id = cur.lastrowid
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({"error": "Contact with this email already exists"}), 400
    conn.close()
    return jsonify({"id": contact_id, "name": name, "email": email_addr, "notes": notes})


@app.route("/api/contacts/<int:contact_id>", methods=["PATCH"])
@login_required
def update_contact(contact_id):
    user = current_user()
    data = request.json or {}
    fields = {k: v for k, v in data.items() if k in ('name', 'email', 'notes')}
    if not fields:
        return jsonify({"error": "No valid fields"}), 400
    conn = get_db()
    set_clause = ", ".join(f"{k} = ?" for k in fields)
    values = list(fields.values()) + [contact_id, user['id']]
    conn.execute(
        f"UPDATE contacts SET {set_clause} WHERE id = ? AND user_id = ?",
        values
    )
    conn.commit()
    row = conn.execute(
        "SELECT id, name, email, notes FROM contacts WHERE id = ?",
        (contact_id,)
    ).fetchone()
    conn.close()
    return jsonify(dict(row) if row else {"error": "Not found"})


@app.route("/api/contacts/<int:contact_id>", methods=["DELETE"])
@login_required
def delete_contact(contact_id):
    user = current_user()
    conn = get_db()
    conn.execute("DELETE FROM contacts WHERE id = ? AND user_id = ?", (contact_id, user['id']))
    conn.commit()
    conn.close()
    return jsonify({"deleted": True})


# ---------------------------------------------------------------------------
# Password change
# ---------------------------------------------------------------------------
@app.route("/api/change_password", methods=["POST"])
@login_required
def change_password():
    user = current_user()
    user_id = user['id']
    data = request.json or {}
    current_pw = data.get("current_password") or ""
    new_pw = data.get("new_password") or ""
    if len(new_pw) < 6:
        return jsonify({"error": "Nové heslo musí mít alespoň 6 znaků"}), 400
    if not verify_user(user['username'], current_pw):
        return jsonify({"error": "Současné heslo je nesprávné"}), 401
    # Re-encrypt DEK with new password
    conn = get_db()
    row = conn.execute("SELECT dek_salt, encrypted_dek FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    try:
        salt = base64.urlsafe_b64decode(row['dek_salt'].encode())
        dek = _decrypt_dek(row['encrypted_dek'], current_pw, salt)
        new_salt = secrets.token_bytes(16)
        new_encrypted_dek = _encrypt_dek(dek, new_pw, new_salt)
    except Exception as e:
        app.logger.error(f'Failed to re-encrypt DEK during password change: {e}')
        return jsonify({"error": "Chyba při změně šifrovacího klíče"}), 500
    new_hash = bcrypt.hashpw(new_pw.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    conn = get_db()
    conn.execute(
        "UPDATE users SET password_hash = ?, dek_salt = ?, encrypted_dek = ? WHERE id = ?",
        (new_hash, base64.urlsafe_b64encode(new_salt).decode(), new_encrypted_dek, user_id)
    )
    conn.commit()
    conn.close()
    _set_user_dek(user_id, dek)
    return jsonify({"status": "changed"})


# ---------------------------------------------------------------------------
# Sync
# ---------------------------------------------------------------------------
@app.route("/api/sync", methods=["POST"])
@login_required
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
    # Auto-create default user if no users exist (first run)
    if not has_users():
        default_pw = os.environ.get("DEFAULT_USER_PASSWORD", "adamec")
        create_user("dominik", default_pw)
        print("=" * 60)
        print(f"Vytvořen výchozí uživatel: dominik / {default_pw}")
        print("Změň heslo po prvním přihlášení v Nastavení.")
        print("=" * 60)
    app.run(
        host=os.environ.get("FLASK_HOST", "127.0.0.1"),
        port=int(os.environ.get("FLASK_PORT", 5005)),
        debug=os.environ.get("FLASK_DEBUG", "false").lower() == "true",
    )
