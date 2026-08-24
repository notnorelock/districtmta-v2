-- Active Record model for the license_suspensions table (gm_licenses) -
-- a time-boxed, staff-issued suspension of one account's one license
-- category. Column shape mirrors AccountPenalty.lua exactly (reason,
-- issued_by_account_id, expires_at, revoked_at, created_at) - same
-- time-boxed-punitive-record-with-a-reason-and-expiry pattern, never
-- hard-deleted (audit trail; revoked_at non-nil means an admin lifted it
-- early via /unsuspendlicense before expires_at was reached).
LicenseSuspension = Model:extend("license_suspensions", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "category", type = "enum", values = { Enums.LicenseCategory.A, Enums.LicenseCategory.B, Enums.LicenseCategory.C, Enums.LicenseCategory.D }, nullable = false },
    { name = "reason", type = "string", length = 255, nullable = true },
    { name = "issued_by_account_id", type = "reference", nullable = true },
    { name = "expires_at", type = "timestamp", nullable = true },
    { name = "revoked_at", type = "timestamp", nullable = true },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("licenseSuspensions", LicenseSuspension, "account_id")
LicenseSuspension:belongsTo("account", Account, "account_id")
LicenseSuspension:belongsTo("issuedBy", Account, "issued_by_account_id")
