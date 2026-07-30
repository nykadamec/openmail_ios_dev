-- Migration 006: add email and from_name to users, populate default user.
ALTER TABLE users ADD COLUMN email TEXT;
ALTER TABLE users ADD COLUMN from_name TEXT;

-- Existing default user 'dominik' gets the configured default email/name.
UPDATE users SET email = 'dominik@adamec.pro', from_name = 'Dominik Adamec' WHERE username = 'dominik';

-- Enforce unique emails after population.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email);
