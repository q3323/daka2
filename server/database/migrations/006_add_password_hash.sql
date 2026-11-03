-- Run once before enabling password login.
-- Existing users have no password and therefore cannot sign in until they
-- register a new account. Password recovery is intentionally unsupported.

ALTER TABLE users
  ADD COLUMN password_hash VARCHAR(255) NULL AFTER role;
