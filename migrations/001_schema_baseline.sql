-- Migration 001: baseline schema for fresh installs.
-- For existing DBs init_db() already created these tables, so this migration is a no-op.
-- It is kept here for documentation and completeness.

-- Users
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    dek_salt TEXT,
    encrypted_dek TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    last_seen TEXT NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id)
);

-- Emails
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

-- Contacts
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

-- Custom folders
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

-- Schema migrations tracking table itself
CREATE TABLE IF NOT EXISTS schema_migrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    filename TEXT UNIQUE NOT NULL,
    applied_at TEXT DEFAULT CURRENT_TIMESTAMP
);
