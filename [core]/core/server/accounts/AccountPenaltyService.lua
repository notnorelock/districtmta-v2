-- Business logic for the account penalty domain (ban/mute/warn/kick) -
-- see docs/Architecture.md's "Account penalties" section.
AccountPenaltyService = AccountPenaltyService or {}

--- @return string current UTC time, "YYYY-MM-DD HH:MM:SS"
local function nowSql()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

--- @param durationSeconds number|nil
-- @return string|nil absolute "YYYY-MM-DD HH:MM:SS" timestamp, or nil for "permanent"
local function expiresAtFromDuration(durationSeconds)
    if durationSeconds == nil then
        return nil
    end
    return os.date("!%Y-%m-%d %H:%M:%S", os.time() + math.floor(durationSeconds))
end

--- Does NOT kick an already-connected player - a ban only blocks future logins.
-- @param accountId number
-- @param options table { durationSeconds: number|nil (nil = permanent),
--        reason: string|nil, mtaSerial: string|nil, issuedByAccountId: number|nil }
-- @param callback function(ok: boolean, penaltyOrError: table|string)
AccountPenaltyService.ban = function(accountId, options, callback)
    options = options or {}
    AccountPenaltyRepository.create({
        accountId = accountId,
        mtaSerial = options.mtaSerial,
        type = Enums.PenaltyType.BAN,
        reason = options.reason,
        issuedByAccountId = options.issuedByAccountId,
        expiresAt = expiresAtFromDuration(options.durationSeconds),
    }, callback)
end

--- @param accountId number
-- @param options table { durationSeconds: number|nil, reason: string|nil, issuedByAccountId: number|nil }
-- @param callback function(ok: boolean, penaltyOrError: table|string)
AccountPenaltyService.mute = function(accountId, options, callback)
    options = options or {}
    AccountPenaltyRepository.create({
        accountId = accountId,
        type = Enums.PenaltyType.MUTE,
        reason = options.reason,
        issuedByAccountId = options.issuedByAccountId,
        expiresAt = expiresAtFromDuration(options.durationSeconds),
    }, callback)
end

--- Pure log entry, never has a duration.
-- @param accountId number
-- @param options table { reason: string|nil, issuedByAccountId: number|nil }
-- @param callback function(ok: boolean, penaltyOrError: table|string)
AccountPenaltyService.warn = function(accountId, options, callback)
    options = options or {}
    AccountPenaltyRepository.create({
        accountId = accountId,
        type = Enums.PenaltyType.WARN,
        reason = options.reason,
        issuedByAccountId = options.issuedByAccountId,
    }, callback)
end

--- Does NOT itself disconnect the player - the caller handles kickPlayer separately.
-- @param accountId number
-- @param options table { reason: string|nil, issuedByAccountId: number|nil }
-- @param callback function(ok: boolean, penaltyOrError: table|string)
AccountPenaltyService.kick = function(accountId, options, callback)
    options = options or {}
    AccountPenaltyRepository.create({
        accountId = accountId,
        type = Enums.PenaltyType.KICK,
        reason = options.reason,
        issuedByAccountId = options.issuedByAccountId,
    }, callback)
end

--- @param penaltyId number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountPenaltyService.revoke = function(penaltyId, callback)
    AccountPenaltyRepository.revoke(penaltyId, callback)
end

--- @param rows table[] rows sharing the same expires_at shape (nullable
--        TIMESTAMP - NULL means permanent)
-- @return table|nil the longest-lasting row - a permanent one (nil
--         expires_at) always wins, otherwise the one expiring furthest
--         in the future wins; nil if `rows` is empty
local function pickLongestLasting(rows)
    local chosen = rows[1]
    for i = 2, #rows do
        local candidate = rows[i]
        if chosen.expires_at ~= nil and (candidate.expires_at == nil or candidate.expires_at > chosen.expires_at) then
            chosen = candidate
        end
    end
    return chosen
end

--- @param accountId number
-- @param onResult function(isBanned: boolean, activeBanOrNil: table|nil)
-- @param onError function(message: string)
AccountPenaltyService.isBanned = function(accountId, onResult, onError)
    AccountPenaltyRepository.findActiveBans(accountId, nowSql(), function(ok, rowsOrError)
        if not ok then
            onError(tostring(rowsOrError))
            return
        end

        if #rowsOrError == 0 then
            onResult(false, nil)
            return
        end

        onResult(true, pickLongestLasting(rowsOrError))
    end)
end

--- @param accountId number
-- @param onResult function(isMuted: boolean, activeMuteOrNil: table|nil)
-- @param onError function(message: string)
AccountPenaltyService.isMuted = function(accountId, onResult, onError)
    AccountPenaltyRepository.findActiveMutes(accountId, nowSql(), function(ok, rowsOrError)
        if not ok then
            onError(tostring(rowsOrError))
            return
        end

        if #rowsOrError == 0 then
            onResult(false, nil)
            return
        end

        onResult(true, pickLongestLasting(rowsOrError))
    end)
end
