-- Active Record model for the account_penalties table - see
-- docs/Architecture.md's "Account penalties" section.
AccountPenalty = Model:extend("account_penalties", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "mta_serial", type = "string", length = 32, nullable = true },
    { name = "type", type = "enum", values = { Enums.PenaltyType.BAN, Enums.PenaltyType.MUTE, Enums.PenaltyType.WARN, Enums.PenaltyType.KICK }, nullable = false },
    { name = "reason", type = "string", length = 255, nullable = true },
    { name = "issued_by_account_id", type = "reference", nullable = true },
    { name = "expires_at", type = "timestamp", nullable = true },
    { name = "revoked_at", type = "timestamp", nullable = true },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("penalties", AccountPenalty, "account_id")
AccountPenalty:belongsTo("account", Account, "account_id")
