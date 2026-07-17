"""Database connection helpers and schema initialization."""
from __future__ import annotations

import sqlite3
from pathlib import Path

from flask import g, current_app

from openmail.config import DB_PATH
from .migrations import run_migrations


BASE_SCHEMA = """
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
    user_id INTEGER,
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

CREATE TABLE IF NOT EXISTS custom_folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    color TEXT DEFAULT '#3B82F6',
    icon TEXT DEFAULT '📁',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, name),
    FOREIGN KEY(user_id) REFERENCES users(id)
);
"""


def get_db() -> sqlite3.Connection:
    """Return a per-request SQLite connection."""
    if 'db' not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
    return g.db


def close_db(e=None) -> None:
    """Close the per-request DB connection."""
    db = g.pop('db', None)
    if db is not None:
        db.close()


def init_db() -> None:
    """Initialize schema and run pending migrations."""
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(BASE_SCHEMA)
    conn.commit()
    user_count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    conn.close()
    run_migrations()
    if user_count == 0:
        from openmail.auth.users import create_user
        from openmail.config import DEFAULT_USER_PASSWORD
        create_user("dominik", DEFAULT_USER_PASSWORD)
        print("=" * 60)
        print(f"Vytvořen výchozí uživatel: dominik / {DEFAULT_USER_PASSWORD}")
        print("Změň heslo v Nastavení po přihlášení.")
        print("=" * 60)
