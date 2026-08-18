-- Active Record model for the admin_duty_sessions table - see
-- docs/Architecture.md's "Admin duty statistics" section.
AdminDutySession = Model:extend("admin_duty_sessions", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "started_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "ended_at", type = "timestamp", nullable = true },
})

Account:hasMany("adminDutySessions", AdminDutySession, "account_id")
AdminDutySession:belongsTo("account", Account, "account_id")
