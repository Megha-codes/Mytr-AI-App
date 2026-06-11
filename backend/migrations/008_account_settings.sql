-- Account-settings & session-management support.
--
--  • terms_accepted_at — timestamp the user explicitly accepted the Terms of
--    Service & Privacy Policy at signup (distinct from research consent).
--  • token_version    — bumped to revoke all outstanding access/refresh tokens
--    for a user. Backs "log out of all devices", password change and account
--    deletion. Issued tokens carry a matching `tv` claim.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMP;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;
