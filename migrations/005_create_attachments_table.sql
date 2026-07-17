-- Migration 005: create dedicated attachments table for referential integrity and GC.
-- Existing attachment metadata remains in emails.attachments JSON column until a future migration migrates it.

CREATE TABLE IF NOT EXISTS attachments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email_id INTEGER NOT NULL,
    filename TEXT NOT NULL,
    content_type TEXT,
    storage_path TEXT NOT NULL,
    size_bytes INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(email_id, filename),
    FOREIGN KEY(email_id) REFERENCES emails(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_attachments_email_id ON attachments(email_id);
