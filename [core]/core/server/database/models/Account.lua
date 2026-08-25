-- Active Record model for the accounts table - see docs/Architecture.md
-- (account lifecycle, roles/permissions) and docs/DatabaseContract.md.
Account = Model:extend("accounts", {
    { name = "id", type = "id", primaryKey = true },
    { name = "mta_serial", type = "string", length = 32, nullable = true },
    { name = "login", type = "string", length = 24, unique = true, nullable = false },
    { name = "email", type = "string", length = 254, unique = true, nullable = false },
    { name = "password_hash", type = "string", length = 60, nullable = false },
    { name = "premium_expires_at", type = "timestamp", nullable = true },
    { name = "role", type = "integer", nullable = false, default = 0 },
    { name = "money", type = "integer", nullable = false, default = 0 },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "updated_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "last_seen_at", type = "timestamp", nullable = true },
    { name = "two_factor_secret", type = "string", length = 32, nullable = true },
    { name = "two_factor_enabled_at", type = "timestamp", nullable = true },
})
