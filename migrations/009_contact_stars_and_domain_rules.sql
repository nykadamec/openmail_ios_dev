-- Migration 009: starred contacts and per-user domain auto-star rules.

ALTER TABLE contacts ADD COLUMN is_starred INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS domain_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    domain TEXT NOT NULL,
    action TEXT NOT NULL DEFAULT 'star' CHECK(action = 'star'),
    enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0, 1)),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, domain, action),
    FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_domain_rules_user ON domain_rules(user_id);
