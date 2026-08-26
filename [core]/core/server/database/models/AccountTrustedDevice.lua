-- Active Record model for the account_trusted_devices table - lets a
-- successful TOTP verification remember "this device" so future logins
-- from it can skip re-entering a code.
AccountTrustedDevice = Model:extend("account_trusted_devices", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    -- Looked up by plain equality to FIND the candidate row (see
    -- AccountTrustedDeviceRepository.findValid) - safe to index/query
    -- directly because it is NOT the secret half of the token; a selector
    -- alone proves nothing (mirrors how a bcrypt salt being public is
    -- fine). High-entropy so it also can't be brute-force-enumerated in
    -- isolation - see AccountTrustedDeviceRepository's generation function.
    { name = "selector", type = "string", length = 64, unique = true, nullable = false },
    -- SHA-256 hex digest of the verifier half - NEVER the raw verifier.
    -- Possessing this hash's plaintext preimage is equivalent to bypassing
    -- 2FA, so it is hashed the same way a password is, see
    -- AccountTrustedDeviceRepository's own comment on why sha256 (not
    -- bcrypt) is the right primitive for THIS value specifically.
    { name = "verifier_hash", type = "string", length = 64, nullable = false },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "expires_at", type = "timestamp", nullable = false },
    -- Updated on every successful trusted-device login - not required for
    -- v1's login flow, but cheap to add now and the natural seed for a
    -- future "manage your devices" list (last used / device count).
    { name = "last_used_at", type = "timestamp", nullable = true },
    -- Set on disableTwoFactor (revokes ALL rows for the account, see
    -- AccountService.disableTwoFactor changes) or a future explicit
    -- per-device "forget this device" action. NULL = still valid subject
    -- to expires_at.
    { name = "revoked_at", type = "timestamp", nullable = true },
})

Account:hasMany("trustedDevices", AccountTrustedDevice, "account_id")
AccountTrustedDevice:belongsTo("account", Account, "account_id")
