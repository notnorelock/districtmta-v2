-- Business logic for the account domain: validation, uniqueness rules,
-- password hashing, and orchestration of AccountRepository.

AccountService = AccountService or {}

local BCRYPT_COST = 10

--- @return string current UTC time, "YYYY-MM-DD HH:MM:SS"
local function nowSql()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

--- @param account table internal account record (snake_case DB columns)
--- @return boolean true if account.premium_expires_at is set and still in the future
AccountService.isPremiumActive = function(account)
    local expiresAt = account and account.premium_expires_at
    return type(expiresAt) == "string" and expiresAt > nowSql()
end

--- @param account table internal account record (snake_case DB columns)
--- @return boolean true if two_factor_enabled_at is genuinely set. NOT a
--- plain `~= nil` check - MTA's MySQL row hydration can return a NULL
--- TIMESTAMP column as an empty string ("") rather than Lua `nil` (same
--- reason AccountService.isPremiumActive above checks
--- `type(x) == "string"` for premium_expires_at instead of `~= nil` -
--- confirmed live: a freshly-migrated two_factor_enabled_at column,
--- correctly NULL in the database, still made every account look
--- 2FA-enabled because `"" ~= nil` is true in Lua).
AccountService.isTwoFactorEnabled = function(account)
    local enabledAt = account and account.two_factor_enabled_at
    return type(enabledAt) == "string" and #enabledAt > 0
end

--- Formats a "YYYY-MM-DD HH:MM:SS" TIMESTAMP string into "DD.MM.YYYY HH:MM"
--- for display to players.
-- @param sqlTimestamp string
-- @return string
AccountService.formatExpiryForDisplay = function(sqlTimestamp)
    local year, month, day, hour, minute = sqlTimestamp:match("^(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
    if not year then
        return sqlTimestamp
    end
    return ("%s.%s.%s %s:%s"):format(day, month, year, hour, minute)
end

function accountServiceFormatExpiryForDisplay(sqlTimestamp) return AccountService.formatExpiryForDisplay(sqlTimestamp) end

--- Maps an internal account record to the safe public DTO sent to CEF.
--- Excludes password_hash and mta_serial.
-- @param account table internal account record (snake_case DB columns)
-- @return table public DTO (camelCase)
AccountService.toPublic = function(account)
    if not account then
        return nil
    end

    return {
        id = account.id,
        login = account.login,
        email = account.email,
        isPremium = AccountService.isPremiumActive(account),
        premiumExpiresAt = AccountService.isPremiumActive(account) and account.premium_expires_at or nil,
        role = account.role or Enums.AccountRole.PLAYER,
        twoFactorEnabled = AccountService.isTwoFactorEnabled(account),
    }
end

--- @param role number
-- @return boolean true if role is one of Enums.AccountRole's values
local function isValidRole(role)
    if type(role) ~= "number" then
        return false
    end
    for _, value in pairs(Enums.AccountRole) do
        if value == role then
            return true
        end
    end
    return false
end

--- Sets an account's global role. Not exposed to the browser/FetchBridge.
-- @param accountId number
-- @param role number one of Enums.AccountRole's values
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountService.setRole = function(accountId, role, callback)
    if not isValidRole(role) then
        callback(false, "Invalid role: " .. tostring(role))
        return
    end
    AccountRepository.updateRole(accountId, role, callback)
end

--- Registers a brand new account with a login + email + password.
-- @param mtaSerial string getPlayerSerial(player) of the registering player
-- @param input table { login: string, email: string, password: string }
-- @param onSuccess function(account: table) internal record, not the DTO
-- @param onError function(code: string, message: string|nil)
AccountService.register = function(mtaSerial, input, onSuccess, onError)
    Logger.debug("AccountService", "register called", { login = input and input.login })

    local login = input and input.login
    local email = input and input.email
    local password = input and input.password

    if type(mtaSerial) ~= "string" or #mtaSerial == 0 then
        onError(ErrorCodes.INTERNAL_ERROR, "Missing MTA serial")
        return
    end

    if type(login) ~= "string" or type(email) ~= "string" or type(password) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "login, email and password are required")
        return
    end

    if not ValidationRules.isValidLogin(login) then
        onError(ErrorCodes.INVALID_LOGIN, "Login must be 3-24 characters: letters, numbers, underscore")
        return
    end

    if not ValidationRules.isValidEmail(email) then
        onError(ErrorCodes.INVALID_EMAIL, "Email address is not valid")
        return
    end

    if not ValidationRules.isValidPassword(password) then
        onError(ErrorCodes.INVALID_PASSWORD, "Password must be 8-128 characters")
        return
    end

    local normalizedLogin = ValidationRules.normalizeLogin(login)
    local normalizedEmail = ValidationRules.normalizeEmail(email)

    AccountRepository.findByLogin(normalizedLogin, function(ok, existing)
        if not ok then
            Logger.error("AccountService", "findByLogin failed", { error = tostring(existing) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        if existing then
            onError(ErrorCodes.ACCOUNT_ALREADY_EXISTS, "Login is already taken")
            return
        end

        AccountRepository.findByEmail(normalizedEmail, function(ok2, existingEmail)
            if not ok2 then
                Logger.error("AccountService", "findByEmail failed", { error = tostring(existingEmail) })
                onError(ErrorCodes.INTERNAL_ERROR)
                return
            end

            if existingEmail then
                onError(ErrorCodes.ACCOUNT_ALREADY_EXISTS, "Email is already registered")
                return
            end

            passwordHash(password, "bcrypt", { cost = BCRYPT_COST }, function(hashOrFalse)
                if hashOrFalse == false then
                    Logger.error("AccountService", "passwordHash failed")
                    onError(ErrorCodes.INTERNAL_ERROR)
                    return
                end

                AccountRepository.create({
                    mtaSerial = mtaSerial,
                    login = normalizedLogin,
                    email = normalizedEmail,
                    passwordHash = hashOrFalse,
                }, function(createOk, accountOrError)
                    if not createOk then
                        Logger.error("AccountService", "AccountRepository.create failed", { error = tostring(accountOrError) })
                        onError(ErrorCodes.ACCOUNT_ALREADY_EXISTS, "Account could not be created")
                        return
                    end

                    Logger.info("AccountService", "Account created", { accountId = accountOrError.id })
                    onSuccess(accountOrError)
                end)
            end)
        end)
    end)
end

local TWO_FACTOR_PENDING_TTL_MS = 120000
-- player -> { accountId: number, expiresAt: number (getTickCount) } -
-- tracks a login that has passed the password check but is waiting on a
-- 2FA code. Keyed by the player element itself, never a client-supplied
-- account id - FetchBridge's own dispatch guarantees `player` always
-- comes from MTA's authoritative connection identity, never from the
-- browser-controlled payload, so a request can never target any account
-- other than the one that just proved password knowledge on THIS
-- connection.
local pendingTwoFactor = {}

--- @param role number one of Enums.AccountRole's values
-- @return boolean true if this role may never log in without confirmed 2FA
AccountService.roleRequiresTwoFactor = function(role)
    return role == Enums.AccountRole.ADMINISTRATOR
        or role == Enums.AccountRole.RCON
        or role == Enums.AccountRole.BOARD
end

--- @param player element
-- @param accountId number
AccountService.beginPendingTwoFactor = function(player, accountId)
    pendingTwoFactor[player] = { accountId = accountId, expiresAt = getTickCount() + TWO_FACTOR_PENDING_TTL_MS }
end

--- Reads the pending entry WITHOUT consuming it on failure - a wrong
--- code is retryable in place (bounded by verifyTwoFactor's own rate
--- limit and this TTL), not a one-shot check that forces a fresh
--- password submit per typo. Only AccountService.verifyTwoFactor clears
--- the entry, and only once verification actually succeeds.
-- @param player element
-- @return number|nil accountId, only if a non-expired pending entry exists
AccountService.peekPendingTwoFactor = function(player)
    local entry = pendingTwoFactor[player]
    if not entry or getTickCount() > entry.expiresAt then
        pendingTwoFactor[player] = nil
        return nil
    end
    return entry.accountId
end

--- @param player element
AccountService.clearPendingTwoFactor = function(player)
    pendingTwoFactor[player] = nil
end

addEventHandler("onPlayerQuit", root, function()
    AccountService.clearPendingTwoFactor(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(pendingTwoFactor) do
        pendingTwoFactor[player] = nil
    end
end)

--- Authenticates a login/email + password pair and, on success, rebinds
--- the account's mta_serial to the logging-in player's current client.
-- @param player element the logging-in player
-- @param mtaSerial string getPlayerSerial(player) of the logging-in player
-- @param input table { login: string, password: string } - `login` accepts
--        either a login or an email
-- @param onSuccess function(account: table)
-- @param onError function(code: string, message: string|nil)
AccountService.login = function(player, mtaSerial, input, onSuccess, onError)
    local identifier = input and input.login
    local password = input and input.password

    if type(identifier) ~= "string" or type(password) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "login and password are required")
        return
    end

    local findAccount
    if ValidationRules.isValidEmail(identifier) then
        findAccount = function(cb) AccountRepository.findByEmail(ValidationRules.normalizeEmail(identifier), cb) end
    else
        findAccount = function(cb) AccountRepository.findByLogin(ValidationRules.normalizeLogin(identifier), cb) end
    end

    findAccount(function(ok, account)
        if not ok then
            Logger.error("AccountService", "login lookup failed", { error = tostring(account) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        if not account then
            onError(ErrorCodes.INVALID_CREDENTIALS, "Login or password is incorrect")
            return
        end

        passwordVerify(password, account.password_hash, {}, function(matches)
            if matches ~= true then
                onError(ErrorCodes.INVALID_CREDENTIALS, "Login or password is incorrect")
                return
            end

            -- Checked after password verification so a banned account's
            -- status is never revealed to someone without the password.
            AccountPenaltyService.isBanned(account.id, function(isBanned, activeBan)
                if isBanned then
                    onError(ErrorCodes.ACCOUNT_BANNED, activeBan.reason or "Account is banned")
                    return
                end

                if account.mta_serial ~= mtaSerial then
                    AccountRepository.updateMtaSerial(account.id, mtaSerial, function() end)
                end

                local twoFactorEnabled = AccountService.isTwoFactorEnabled(account)

                if not twoFactorEnabled and AccountService.roleRequiresTwoFactor(account.role) then
                    -- Privileged role, 2FA never confirmed (a still-
                    -- pending, unconfirmed secret counts as "not enabled"
                    -- too - see Account.lua's column comment). Per
                    -- explicit product decision, blocked entirely rather
                    -- than let in and shown a forced-setup screen - an
                    -- unconfigured privileged account should require
                    -- out-of-band intervention (DB admin/future web
                    -- panel), not be self-serviceable mid-login where a
                    -- compromised password alone would otherwise be
                    -- enough to reach a privileged session. UNCHANGED by
                    -- the trusted-device feature below: a trust token can
                    -- only ever exist for an account that has confirmed
                    -- 2FA (issueTrustedDevice is only ever called from the
                    -- verifyTwoFactor success path), so an account that
                    -- reaches this branch structurally cannot have any
                    -- valid row in account_trusted_devices in the first
                    -- place - two independent reasons this can never be
                    -- bypassed, not one.
                    onError(ErrorCodes.TWO_FACTOR_SETUP_REQUIRED, "Two-factor authentication must be configured for this account before it can log in")
                    return
                end

                if twoFactorEnabled then
                    local trustToken = input and input.trustToken

                    AccountService.checkTrustedDevice(account.id, trustToken, function(isTrusted)
                        if isTrusted then
                            Logger.security("AccountService", "Login via trusted device, 2FA challenge skipped", { accountId = account.id })
                            onSuccess(account)
                            return
                        end

                        AccountService.beginPendingTwoFactor(player, account.id)
                        onError(ErrorCodes.TWO_FACTOR_REQUIRED)
                    end)
                    return
                end

                onSuccess(account)
            end, function(message)
                Logger.error("AccountService", "isBanned check failed", { error = message })
                onError(ErrorCodes.INTERNAL_ERROR)
            end)
        end)
    end)
end

--- Changes an already-authenticated player's own password after
--- verifying their current one. No session/serial invalidation needed -
--- this codebase has no multi-session concept; mta_serial is already
--- 1:1 rebound on every login (see AccountService.login above), so a
--- plain hash update is sufficient here.
-- @param player element the currently-authenticated player
-- @param input table { currentPassword: string, newPassword: string }
-- @param onSuccess function()
-- @param onError function(code: string, message: string|nil)
AccountService.changePassword = function(player, input, onSuccess, onError)
    local account = PlayerService.getAccount(player)
    if not account then
        onError(ErrorCodes.NOT_AUTHENTICATED)
        return
    end

    local currentPassword = input and input.currentPassword
    local newPassword = input and input.newPassword

    if type(currentPassword) ~= "string" or type(newPassword) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "currentPassword and newPassword are required")
        return
    end

    if not ValidationRules.isValidPassword(newPassword) then
        onError(ErrorCodes.INVALID_PASSWORD, "Password must be 8-128 characters")
        return
    end

    passwordVerify(currentPassword, account.password_hash, {}, function(matches)
        if matches ~= true then
            onError(ErrorCodes.INVALID_CREDENTIALS, "Current password is incorrect")
            return
        end

        passwordHash(newPassword, "bcrypt", { cost = BCRYPT_COST }, function(hashOrFalse)
            if hashOrFalse == false then
                Logger.error("AccountService", "passwordHash failed", { accountId = account.id })
                onError(ErrorCodes.INTERNAL_ERROR)
                return
            end

            AccountRepository.updatePasswordHash(account.id, hashOrFalse, function(ok, affectedOrError)
                if not ok then
                    Logger.error("AccountService", "updatePasswordHash failed", { accountId = account.id, error = tostring(affectedOrError) })
                    onError(ErrorCodes.INTERNAL_ERROR)
                    return
                end

                -- PlayerService.getAccount(player) returns the SAME live
                -- table PlayerService holds for the session (confirmed:
                -- PlayerService.getAccount = function(player) return
                -- accountContexts[player] end) - keeping this in sync
                -- means a second change-password attempt in the same
                -- session verifies against the fresh hash without a re-fetch.
                account.password_hash = hashOrFalse
                Logger.security("AccountService", "Password changed", { accountId = account.id })
                onSuccess()
            end)
        end)
    end)
end

--- Completes a login paused by AccountService.login's TWO_FACTOR_REQUIRED
--- branch above. The pending account id comes ONLY from
--- AccountService.peekPendingTwoFactor(player) - never from the payload -
--- so a request cannot target any account other than the one that just
--- proved password knowledge on THIS connection.
-- @param player element
-- @param input table { code: string, trustDevice: boolean|nil } - 6-digit
--        TOTP code, and whether to issue a trusted-device bypass token
-- @param onSuccess function(account: table, trustToken: string|nil)
--        trustToken is nil unless input.trustDevice was true AND issuing
--        one succeeded
-- @param onError function(code: string, message: string|nil)
AccountService.verifyTwoFactor = function(player, input, onSuccess, onError)
    local code = input and input.code
    local trustDevice = input and input.trustDevice == true

    if type(code) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "code is required")
        return
    end

    local accountId = AccountService.peekPendingTwoFactor(player)
    if not accountId then
        onError(ErrorCodes.TWO_FACTOR_SESSION_EXPIRED, "Login expired, please sign in again")
        return
    end

    AccountRepository.findById(accountId, function(ok, account)
        if not ok or not account then
            Logger.error("AccountService", "verifyTwoFactor: account lookup failed", { accountId = accountId, error = tostring(account) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        if not AccountService.isTwoFactorEnabled(account) or type(account.two_factor_secret) ~= "string" or #account.two_factor_secret == 0 then
            -- Defensive only (e.g. a disable-2FA race with an in-flight
            -- login) - should be unreachable in normal flow. Uses the
            -- same "empty string, not nil" -safe checks as
            -- AccountService.isTwoFactorEnabled - see its own comment.
            AccountService.clearPendingTwoFactor(player)
            onError(ErrorCodes.TWO_FACTOR_SESSION_EXPIRED, "Two-factor authentication is no longer configured for this account")
            return
        end

        if not Totp.verify(account.two_factor_secret, code) then
            Logger.security("AccountService", "Two-factor code rejected", { accountId = account.id })
            -- Deliberately NOT clearing pendingTwoFactor here - a wrong
            -- code is retryable in place, see peekPendingTwoFactor's own
            -- comment. Bounded by rate limiting + the 2-minute TTL.
            onError(ErrorCodes.INVALID_TWO_FACTOR_CODE, "Invalid code")
            return
        end

        AccountService.clearPendingTwoFactor(player)

        if trustDevice then
            AccountService.issueTrustedDevice(account.id, function(rawToken)
                onSuccess(account, rawToken)
            end, function(issueCode, issueMessage)
                -- Trust-token issuance failing must NEVER fail the login
                -- that already succeeded on a correct TOTP code - log and
                -- proceed without a token, same "degrade gracefully"
                -- reasoning as this file's own fire-and-forget calls
                -- elsewhere (e.g. touchLastSeen).
                Logger.error("AccountService", "issueTrustedDevice failed post-verify", { accountId = account.id, code = issueCode, message = issueMessage })
                onSuccess(account, nil)
            end)
            return
        end

        onSuccess(account, nil)
    end)
end

--- Generates a new pending TOTP secret for the current player's account
--- and returns it + an otpauth:// URI for QR rendering. Does NOT enable
--- 2FA - see confirmTwoFactorSetup, which is the only path that does.
--- Refuses if 2FA is already confirmed/enabled (must disable first via
--- disableTwoFactor, which requires the current password) so a hijacked
--- in-game session alone can't silently swap the secret out from under
--- the real owner.
-- @param player element
-- @param onSuccess function(secret: string, otpauthUri: string)
-- @param onError function(code: string, message: string|nil)
AccountService.beginTwoFactorSetup = function(player, onSuccess, onError)
    local account = PlayerService.getAccount(player)
    if not account then
        onError(ErrorCodes.NOT_AUTHENTICATED)
        return
    end

    if AccountService.isTwoFactorEnabled(account) then
        onError(ErrorCodes.TWO_FACTOR_ALREADY_ENABLED, "Two-factor authentication is already enabled")
        return
    end

    local secret = Totp.generateSecretKey(16)

    AccountRepository.setTwoFactorPendingSecret(account.id, secret, function(ok, affectedOrError)
        if not ok then
            Logger.error("AccountService", "setTwoFactorPendingSecret failed", { accountId = account.id, error = tostring(affectedOrError) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        account.two_factor_secret = secret
        -- issuer/label per the otpauth Key Uri Format - shows in the
        -- authenticator app's list as "District (login)". Both segments
        -- percent-encoded even though `login` is already restricted to
        -- [A-Za-z0-9_] by ValidationRules and never needs escaping today
        -- - unconditional encoding means this doesn't quietly break if
        -- that pattern is ever loosened later.
        local issuer = "District"
        local otpauthUri = ("otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30"):format(
            issuer, account.login, secret, issuer
        )

        Logger.security("AccountService", "Two-factor setup started", { accountId = account.id })
        onSuccess(secret, otpauthUri)
    end)
end

--- Confirms a pending secret (started via beginTwoFactorSetup) by
--- verifying the user's first live code against it, THEN persists it as
--- enabled. This is the proof-of-possession step - without it, a typo'd
--- or never-scanned secret could get "enabled" and permanently lock the
--- account out (or, for a privileged role, block all future logins per
--- AccountService.roleRequiresTwoFactor).
-- @param player element
-- @param input table { code: string }
-- @param onSuccess function()
-- @param onError function(code: string, message: string|nil)
AccountService.confirmTwoFactorSetup = function(player, input, onSuccess, onError)
    local account = PlayerService.getAccount(player)
    if not account then
        onError(ErrorCodes.NOT_AUTHENTICATED)
        return
    end

    local code = input and input.code
    if type(code) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "code is required")
        return
    end

    if type(account.two_factor_secret) ~= "string" or #account.two_factor_secret == 0 then
        onError(ErrorCodes.TWO_FACTOR_SETUP_REQUIRED, "Call account.enableTwoFactor first")
        return
    end

    if not Totp.verify(account.two_factor_secret, code) then
        onError(ErrorCodes.INVALID_TWO_FACTOR_CODE, "Invalid code")
        return
    end

    AccountRepository.confirmTwoFactor(account.id, function(ok, affectedOrError)
        if not ok then
            Logger.error("AccountService", "confirmTwoFactor failed", { accountId = account.id, error = tostring(affectedOrError) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        account.two_factor_enabled_at = os.date("!%Y-%m-%d %H:%M:%S")
        Logger.security("AccountService", "Two-factor authentication enabled", { accountId = account.id })
        onSuccess()
    end)
end

--- Disables 2FA after re-verifying the current password - same
--- "re-verify before mutating" reasoning as changePassword above (a
--- hijacked in-game session alone shouldn't be enough to strip an
--- account's 2FA protection).
-- @param player element
-- @param input table { currentPassword: string }
-- @param onSuccess function()
-- @param onError function(code: string, message: string|nil)
AccountService.disableTwoFactor = function(player, input, onSuccess, onError)
    local account = PlayerService.getAccount(player)
    if not account then
        onError(ErrorCodes.NOT_AUTHENTICATED)
        return
    end

    local currentPassword = input and input.currentPassword
    if type(currentPassword) ~= "string" then
        onError(ErrorCodes.INVALID_ARGUMENTS, "currentPassword is required")
        return
    end

    if AccountService.roleRequiresTwoFactor(account.role) then
        -- Mirrors login's own block, symmetrically: a privileged account
        -- may not remove the one thing that lets it log in at all.
        onError(ErrorCodes.TWO_FACTOR_REQUIRED_FOR_ROLE, "Two-factor authentication cannot be disabled for this account's role")
        return
    end

    passwordVerify(currentPassword, account.password_hash, {}, function(matches)
        if matches ~= true then
            onError(ErrorCodes.INVALID_CREDENTIALS, "Current password is incorrect")
            return
        end

        AccountRepository.clearTwoFactor(account.id, function(ok, affectedOrError)
            if not ok then
                Logger.error("AccountService", "clearTwoFactor failed", { accountId = account.id, error = tostring(affectedOrError) })
                onError(ErrorCodes.INTERNAL_ERROR)
                return
            end

            account.two_factor_secret = nil
            account.two_factor_enabled_at = nil

            -- Disabling 2FA must revoke every outstanding trusted device -
            -- otherwise a device trusted while 2FA was on would silently
            -- keep bypassing password-only re-auth even after the owner
            -- explicitly turned 2FA off, and (if they later re-enable it)
            -- potentially with a BRAND NEW secret the old trust decision
            -- was never made against. A trust token's entire meaning is
            -- "this device already proved a 2FA code for the CURRENT 2FA
            -- configuration" - once that configuration is gone, every such
            -- proof is stale. Fire-and-forget, same reasoning as
            -- touchLastSeen elsewhere in this file - a failure here must
            -- not fail the disable itself (2FA is already off in the
            -- source of truth), just gets logged.
            AccountTrustedDeviceRepository.revokeAllForAccount(account.id, function(revokeOk, revokeErr)
                if not revokeOk then
                    Logger.error("AccountService", "revokeAllForAccount failed after disableTwoFactor", { accountId = account.id, error = tostring(revokeErr) })
                end
            end)

            Logger.security("AccountService", "Two-factor authentication disabled", { accountId = account.id })
            onSuccess()
        end)
    end)
end

--- Checks whether `rawToken` is a currently-valid trusted-device token for
--- `accountId`. Called ONLY from within login's `if twoFactorEnabled then`
--- branch (see that function's own comment) - never a standalone bypass
--- path. A missing/malformed/expired/revoked/wrong-account token is
--- treated identically (isTrusted = false) - no error code is surfaced for
--- an invalid token, it just falls through to the normal 2FA challenge as
--- if no token had ever been sent.
-- @param accountId number
-- @param rawToken string|nil client-supplied trustToken from the login payload
-- @param onResult function(isTrusted: boolean)
AccountService.checkTrustedDevice = function(accountId, rawToken, onResult)
    if type(rawToken) ~= "string" or #rawToken == 0 then
        onResult(false)
        return
    end

    AccountTrustedDeviceRepository.findValid(rawToken, function(ok, result)
        if not ok then
            Logger.error("AccountService", "checkTrustedDevice lookup failed", { error = tostring(result) })
            onResult(false)
            return
        end

        if not result.valid or result.accountId ~= accountId then
            -- accountId mismatch: a token issued for account A submitted
            -- alongside a login/password pair that resolved to account B.
            -- Never trust the token to identify WHICH account it's for -
            -- only to confirm trust for the account already authenticated
            -- by password in this same call.
            onResult(false)
            return
        end

        AccountTrustedDeviceRepository.touchLastUsed(result.id)
        onResult(true)
    end)
end

--- Issues a new trusted-device token for the CURRENTLY authenticated
--- player's account. Called only from the verifyTwoFactor success path
--- (never standalone) - see AccountEndpoints.lua's auth.verifyTwoFactor
--- handler, gated behind an explicit opt-in checkbox, default OFF (mirrors
--- "remember me"'s own default-off pattern).
-- @param accountId number an account that JUST proved a live TOTP code
-- @param onSuccess function(rawToken: string)
-- @param onError function(code: string, message: string|nil)
AccountService.issueTrustedDevice = function(accountId, onSuccess, onError)
    AccountTrustedDeviceRepository.create(accountId, function(ok, tokenOrError)
        if not ok then
            Logger.error("AccountService", "issueTrustedDevice failed", { accountId = accountId, error = tostring(tokenOrError) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        Logger.security("AccountService", "Trusted device issued", { accountId = accountId })
        onSuccess(tokenOrError)
    end)
end

--- Looks up the account already bound to a player's MTA serial, if any.
--- UX shortcut only, not authentication.
-- @param mtaSerial string
-- @param onSuccess function(account: table|nil) nil means "no account bound yet"
-- @param onError function(code: string, message: string|nil)
AccountService.findByMtaSerial = function(mtaSerial, onSuccess, onError)
    AccountRepository.findByMtaSerial(mtaSerial, function(ok, account)
        if not ok then
            Logger.error("AccountService", "findByMtaSerial failed", { error = tostring(account) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        onSuccess(account)
    end)
end

--- Resolves an account context for a connecting player once their account
--- id is known (either just-created via register, or authenticated via
--- login). Also clears a lapsed premium_expires_at back to NULL.
-- @param player element
-- @param accountId number
-- @param onSuccess function(account: table)
-- @param onError function(code: string, message: string|nil)
AccountService.resolveForPlayer = function(player, accountId, onSuccess, onError)
    AccountRepository.findById(accountId, function(ok, account)
        if not ok then
            Logger.error("AccountService", "findById failed", { error = tostring(account) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        if not account then
            onError(ErrorCodes.ACCOUNT_NOT_FOUND)
            return
        end

        AccountRepository.touchLastSeen(account.id, function() end)

        if type(account.premium_expires_at) == "string" and not AccountService.isPremiumActive(account) then
            AccountRepository.clearExpiredPremium(account.id, function() end)
            account.premium_expires_at = nil
        end

        PlayerService.setAccountContext(player, account)
        onSuccess(account)
    end)
end
