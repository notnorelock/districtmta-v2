-- Active Record model for the reports table - see docs/Architecture.md's
-- "Reports" section.
Report = Model:extend("reports", {
    { name = "id", type = "id", primaryKey = true },
    { name = "reporter_account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "reported_account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "reason", type = "string", length = 255, nullable = false },
    { name = "status", type = "enum", values = { Enums.ReportStatus.OPEN, Enums.ReportStatus.RESOLVED }, nullable = false, default = Enums.ReportStatus.OPEN },
    { name = "resolved_by_account_id", type = "reference", nullable = true },
    { name = "resolved_at", type = "timestamp", nullable = true },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("reportsFiled", Report, "reporter_account_id")
Account:hasMany("reportsReceived", Report, "reported_account_id")
Report:belongsTo("reporter", Account, "reporter_account_id")
Report:belongsTo("reported", Account, "reported_account_id")
