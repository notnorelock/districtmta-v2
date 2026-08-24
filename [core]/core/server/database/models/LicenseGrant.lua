-- Active Record model for the license_grants table (gm_licenses) - one
-- row per (account_id, category) pair the account has passed the exam
-- for. No DB-level UNIQUE constraint (Schema.lua's column DSL has no
-- concept of one - see Vehicle.lua's own precedent); re-granting a
-- category the account already holds is rejected at the service layer
-- (gm_licenses/server/LicenseExamService.lua's eligibility check), never here.
LicenseGrant = Model:extend("license_grants", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "category", type = "enum", values = { Enums.LicenseCategory.A, Enums.LicenseCategory.B, Enums.LicenseCategory.C, Enums.LicenseCategory.D }, nullable = false },
    { name = "granted_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("licenseGrants", LicenseGrant, "account_id")
LicenseGrant:belongsTo("account", Account, "account_id")
