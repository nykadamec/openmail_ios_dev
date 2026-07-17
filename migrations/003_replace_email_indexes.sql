-- Migration 003: replace low-selectivity single-column indexes with per-user composite indexes.

-- Drop old single-column indexes
DROP INDEX IF EXISTS idx_emails_direction;
DROP INDEX IF EXISTS idx_emails_folder;
DROP INDEX IF EXISTS idx_emails_starred;
DROP INDEX IF EXISTS idx_emails_spam;
DROP INDEX IF EXISTS idx_emails_trash;
DROP INDEX IF EXISTS idx_emails_read;
DROP INDEX IF EXISTS idx_emails_custom_folder;
DROP INDEX IF EXISTS idx_emails_created;

-- Per-user composite covering indexes for the main app queries
CREATE INDEX IF NOT EXISTS idx_emails_user_folder_created
    ON emails(user_id, direction, folder, is_trash, is_spam, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emails_user_starred
    ON emails(user_id, is_starred, is_trash, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emails_user_spam
    ON emails(user_id, is_spam, is_trash, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emails_user_unread
    ON emails(user_id, direction, is_read, is_trash, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emails_user_trash
    ON emails(user_id, is_trash, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_emails_user_custom_folder
    ON emails(user_id, custom_folder_id, is_trash, created_at DESC);

-- Resend deduplication lookup
CREATE INDEX IF NOT EXISTS idx_emails_resend_id ON emails(resend_id);
