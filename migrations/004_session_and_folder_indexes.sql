-- Migration 004: indexes for session cleanup and folder/contact ordering.

-- Session cleanup by last_seen
CREATE INDEX IF NOT EXISTS idx_sessions_last_seen ON sessions(last_seen);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);

-- Folder/contact ordering
CREATE INDEX IF NOT EXISTS idx_custom_folders_user_name ON custom_folders(user_id, name);
CREATE INDEX IF NOT EXISTS idx_contacts_user_name ON contacts(user_id, name);
