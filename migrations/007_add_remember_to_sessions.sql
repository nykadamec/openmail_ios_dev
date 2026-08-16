-- Migration 007: add remember-me flag to sessions.

ALTER TABLE sessions ADD COLUMN remember INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_sessions_remember_last_seen ON sessions(remember, last_seen);
