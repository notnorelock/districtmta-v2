-- Thin facade over the AccountTrustedDevice Active Record model. See
-- AccountTrustedDevice.lua's own column comments for the selector/verifier
-- design and why verifier_hash uses sha256, not bcrypt.
AccountTrustedDeviceRepository = AccountTrustedDeviceRepository or {}

local ALLOWED_BYTE_RANGES = { { 48, 57 }, { 65, 90 }, { 97, 122 } } -- 0-9, A-Z, a-z
local TRUST_DURATION_SECONDS = 30 * 24 * 60 * 60 -- 30 days

-- Own seed call rather than relying on SessionKeyService.lua's - this file
-- loads before SessionKeyService.lua in meta.xml, so math.random's state
-- can't be assumed already seeded when this module first runs. Redundant
-- if something else also seeds later; harmless either way.
math.randomseed(getTickCount())

local function randomString(length)
    local chars = {}
    for i = 1, length do
        local range = ALLOWED_BYTE_RANGES[math.random(1, 3)]
        chars[i] = string.char(math.random(range[1], range[2]))
    end
    return table.concat(chars)
end

-- Same construction as SessionKeyService.lua's generateSessionKey: MTA has
-- no native CSPRNG (no os.urandom/crypto.randomBytes equivalent), so
-- math.random alone is not trustworthy for a value whose possession is
-- equivalent to bypassing 2FA. Mitigated the same way SessionKeyService
-- already does project-wide: fold high-resolution wall time + a long
-- math.random string through sha256, a one-way function - even if
-- math.random's internal state were predicted, deriving the PRE-image (the
-- random string) from a sha256 OUTPUT is not feasible, so what actually
-- ships to the client is not simply "math.random," it's "sha256 of
-- math.random plus other inputs." This does not increase the underlying
-- entropy above whatever math.random actually provides, but it does
-- prevent an attacker who can query many tokens from directly inferring or
-- replaying the PRNG's raw output.
--
-- Honest risk statement: MTA:SA's Lua math.random is a standard PRNG (not
-- cryptographically secure), seeded once per resource start. The
-- mitigation above raises the bar significantly above a raw math.random
-- guess, and matches this project's own existing bar for "a token good
-- enough to authenticate a session" (SessionKeyService). It is NOT a
-- formal cryptographic guarantee equivalent to crypto.randomBytes. This is
-- an accepted, precedented risk in this codebase, not a new one introduced
-- here - there is no better native primitive to reach for.
local function generateTokenHalf(length)
    local timestamp = getRealTime().timestamp
    return sha256(string.format("%d:%s:%d", timestamp, randomString(length), math.random(1, 2 ^ 31)))
end

--- Issues a brand-new trusted-device token for an account. Returns the RAW
--- opaque token string - the ONLY moment it ever exists outside whatever
--- the client stores locally. Nothing server-side keeps it after this call
--- returns (only verifier_hash is persisted).
-- @param accountId number
-- @param callback function(ok: boolean, rawTokenOrError: string)
AccountTrustedDeviceRepository.create = function(accountId, callback)
    local rawSelector = generateTokenHalf(12)
    local rawVerifier = generateTokenHalf(24)
    local verifierHash = sha256(rawVerifier)
    local expiresAt = os.date("!%Y-%m-%d %H:%M:%S", os.time() + TRUST_DURATION_SECONDS)

    AccountTrustedDevice:create({
        account_id = accountId,
        selector = rawSelector,
        verifier_hash = verifierHash,
        expires_at = expiresAt,
    }, function(ok, rowOrError)
        if not ok then
            callback(false, rowOrError)
            return
        end
        callback(true, rawSelector .. "." .. rawVerifier)
    end)
end

--- Validates a raw client-supplied token against the stored hash. Never
--- reversible - looks the row up by `selector` (plain equality, safe - see
--- AccountTrustedDevice.lua's own comment on why the selector isn't
--- secret), then re-hashes the SUBMITTED verifier and compares against the
--- stored verifier_hash. Also enforces not-expired and not-revoked here so
--- every caller gets a single boolean answer instead of re-deriving that
--- logic itself.
-- @param rawToken string as issued by .create, "<selector>.<verifier>"
-- @param callback function(ok: boolean, resultOrError: table|string)
--        resultOrError on ok=true: { valid: boolean, accountId: number|nil, id: number|nil }
AccountTrustedDeviceRepository.findValid = function(rawToken, callback)
    if type(rawToken) ~= "string" then
        callback(true, { valid = false })
        return
    end

    local selector, verifier = rawToken:match("^([^.]+)%.(.+)$")
    if not selector or not verifier then
        callback(true, { valid = false })
        return
    end

    AccountTrustedDevice:where("selector", selector):first(function(ok, row)
        if not ok then
            callback(false, row)
            return
        end

        if not row then
            callback(true, { valid = false })
            return
        end

        if type(row.revoked_at) == "string" and #row.revoked_at > 0 then
            callback(true, { valid = false })
            return
        end

        local nowSql = os.date("!%Y-%m-%d %H:%M:%S")
        if row.expires_at <= nowSql then
            callback(true, { valid = false })
            return
        end

        if sha256(verifier) ~= row.verifier_hash then
            callback(true, { valid = false })
            return
        end

        callback(true, { valid = true, accountId = row.account_id, id = row.id })
    end)
end

--- Updates last_used_at - fire-and-forget, called after a successful
--- trusted-device login. Not required for correctness, only for a future
--- device-management UI.
-- @param id number account_trusted_devices row id
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)|nil
AccountTrustedDeviceRepository.touchLastUsed = function(id, callback)
    AccountTrustedDevice:query():where("id", id):update({
        last_used_at = os.date("!%Y-%m-%d %H:%M:%S"),
    }, callback or function() end)
end

--- Revokes every trusted device for an account - called from
--- AccountService.disableTwoFactor. Unconditional (every row, not just
--- unexpired ones) - harmless no-op on an already-expired row, and cheaper
--- than filtering.
-- @param accountId number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountTrustedDeviceRepository.revokeAllForAccount = function(accountId, callback)
    AccountTrustedDevice:query()
        :where("account_id", accountId)
        :where("revoked_at", "IS", Model.NULL)
        :update({ revoked_at = os.date("!%Y-%m-%d %H:%M:%S") }, callback)
end
