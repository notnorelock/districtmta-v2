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

--- Authenticates a login/email + password pair and, on success, rebinds
--- the account's mta_serial to the logging-in player's current client.
-- @param mtaSerial string getPlayerSerial(player) of the logging-in player
-- @param input table { login: string, password: string } - `login` accepts
--        either a login or an email
-- @param onSuccess function(account: table)
-- @param onError function(code: string, message: string|nil)
AccountService.login = function(mtaSerial, input, onSuccess, onError)
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
