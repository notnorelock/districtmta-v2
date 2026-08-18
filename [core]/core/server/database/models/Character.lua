-- Placeholder model - see docs/DatabaseContract.md's "Characters table" section.
Character = Model:extend("characters", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "name", type = "string", length = 24, nullable = false },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "updated_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("characters", Character, "account_id")
Character:belongsTo("account", Account, "account_id")
