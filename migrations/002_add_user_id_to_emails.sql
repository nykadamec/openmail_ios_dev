-- Migration 002: add user_id to emails and backfill from default user (id=1).
-- This is required before replacing indexes with per-user composite indexes.

-- SQLite supports ALTER TABLE ADD COLUMN.
ALTER TABLE emails ADD COLUMN user_id INTEGER;

-- Backfill existing rows to the default user (id=1). In single-user installs this is correct.
-- If multiple users already exist, this migration assumes user 1 owns all legacy email data.
UPDATE emails SET user_id = 1 WHERE user_id IS NULL;

-- Once backfilled, enforce NOT NULL.
-- SQLite does not support ALTER COLUMN; recreate the table if NOT NULL is strictly required.
-- For now we keep it nullable in schema, but app code will always set it.
