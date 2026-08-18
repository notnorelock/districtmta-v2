-- Admin duty/activity statistics - see docs/Architecture.md's "Admin
-- duty statistics" section.
AdminDutyStatsService = AdminDutyStatsService or {}

local openSessionIdByAccountId = {}

--- @param accountId number
-- @param onSuccess function(session: table)|nil
-- @param onError function(message: string)|nil
AdminDutyStatsService.startSession = function(accountId, onSuccess, onError)
    AdminDutySessionRepository.start(accountId, function(ok, sessionOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "Failed to start duty session", {
                accountId = accountId, error = tostring(sessionOrError),
            })
            if onError then onError(tostring(sessionOrError)) end
            return
        end

        openSessionIdByAccountId[accountId] = sessionOrError.id
        if onSuccess then onSuccess(sessionOrError) end
    end)
end

--- No-op if no session is tracked in memory (e.g. after a `core`
--- restart mid-session) - closeOrphanedSessions recovers that case instead.
-- @param accountId number
-- @param onSuccess function()|nil
-- @param onError function(message: string)|nil
AdminDutyStatsService.finishSession = function(accountId, onSuccess, onError)
    local sessionId = openSessionIdByAccountId[accountId]
    if not sessionId then
        if onSuccess then onSuccess() end
        return
    end

    openSessionIdByAccountId[accountId] = nil

    AdminDutySessionRepository.finish(sessionId, function(ok, affectedOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "Failed to finish duty session", {
                accountId = accountId, sessionId = sessionId, error = tostring(affectedOrError),
            })
            if onError then onError(tostring(affectedOrError)) end
            return
        end
        if onSuccess then onSuccess() end
    end)
end

--- @param isoTimestamp string "YYYY-MM-DD HH:MM:SS" (UTC)
-- @return number unix seconds
local function parseSqlTimestamp(isoTimestamp)
    local year, month, day, hour, min, sec = isoTimestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    return os.time({
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec),
    })
end

--- @param sessions table[] admin_duty_sessions rows for one account
-- @return number total seconds across every session - an open one
--         (ended_at nil) counts up to right now
local function totalDutySeconds(sessions)
    local total = 0
    local now = os.time()

    for _, session in ipairs(sessions) do
        local startedAt = parseSqlTimestamp(session.started_at)
        local endedAt = session.ended_at and parseSqlTimestamp(session.ended_at) or now
        total = total + math.max(0, endedAt - startedAt)
    end

    return total
end

--- Full stats bundle for one admin account.
-- @param accountId number
-- @param callback function(ok: boolean, statsOrError: table|string)
--        stats = { totalDutySeconds, sessionCount, penaltiesIssued, reportsResolved }
AdminDutyStatsService.statsForAccount = function(accountId, callback)
    local stats = {}
    local pending = 3
    local failed = false

    local function maybeDone()
        pending = pending - 1
        if pending > 0 then
            return
        end
        if failed then
            callback(false, "One or more stat queries failed - see server log")
            return
        end
        callback(true, stats)
    end

    AdminDutySessionRepository.findByAccountId(accountId, function(ok, sessionsOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "findByAccountId failed", { accountId = accountId, error = tostring(sessionsOrError) })
            failed = true
            maybeDone()
            return
        end
        stats.totalDutySeconds = totalDutySeconds(sessionsOrError)
        stats.sessionCount = #sessionsOrError
        maybeDone()
    end)

    AccountPenaltyRepository.countIssuedByAccountId(accountId, function(ok, countOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "countIssuedByAccountId failed", { accountId = accountId, error = tostring(countOrError) })
            failed = true
            maybeDone()
            return
        end
        stats.penaltiesIssued = countOrError
        maybeDone()
    end)

    ReportRepository.countResolvedByAccountId(accountId, function(ok, countOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "countResolvedByAccountId failed", { accountId = accountId, error = tostring(countOrError) })
            failed = true
            maybeDone()
            return
        end
        stats.reportsResolved = countOrError
        maybeDone()
    end)
end

--- Stats for every account role > PLAYER (see docs/Architecture.md).
-- @param callback function(ok: boolean, entriesOrError: table|string)
--        entries = array of { accountId, login, ...statsForAccount's fields }
AdminDutyStatsService.statsForEveryAdmin = function(callback)
    Account:where("role", ">", Enums.AccountRole.PLAYER):get(function(ok, accountsOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "Account:where(role) failed", { error = tostring(accountsOrError) })
            callback(false, accountsOrError)
            return
        end

        if #accountsOrError == 0 then
            callback(true, {})
            return
        end

        local entries = {}
        local remaining = #accountsOrError

        for i, account in ipairs(accountsOrError) do
            AdminDutyStatsService.statsForAccount(account.id, function(ok, statsOrError)
                if ok then
                    entries[i] = {
                        accountId = account.id,
                        login = account.login,
                        role = account.role,
                        totalDutySeconds = statsOrError.totalDutySeconds,
                        sessionCount = statsOrError.sessionCount,
                        penaltiesIssued = statsOrError.penaltiesIssued,
                        reportsResolved = statsOrError.reportsResolved,
                    }
                else
                    Logger.error("AdminDutyStatsService", "statsForAccount failed while building full admin list", {
                        accountId = account.id, error = tostring(statsOrError),
                    })
                    entries[i] = {
                        accountId = account.id, login = account.login, role = account.role,
                        totalDutySeconds = 0, sessionCount = 0, penaltiesIssued = 0, reportsResolved = 0,
                    }
                end

                remaining = remaining - 1
                if remaining <= 0 then
                    callback(true, entries)
                end
            end)
        end
    end)
end

-- Closes every session left open by an unclean previous stop. Waits for
-- Events.DATABASE_READY, not onResourceStart - see DatabaseContract.md.
local function closeOrphanedSessions()
    AdminDutySessionRepository.findOpen(function(ok, sessionsOrError)
        if not ok then
            Logger.error("AdminDutyStatsService", "findOpen failed while closing orphaned sessions", { error = tostring(sessionsOrError) })
            return
        end

        for _, session in ipairs(sessionsOrError) do
            AdminDutySessionRepository.finish(session.id, function(finishOk, affectedOrError)
                if not finishOk then
                    Logger.error("AdminDutyStatsService", "Failed to close orphaned duty session", {
                        sessionId = session.id, accountId = session.account_id, error = tostring(affectedOrError),
                    })
                end
            end)
        end

        if #sessionsOrError > 0 then
            Logger.info("AdminDutyStatsService", "Closed orphaned duty sessions from an unclean previous stop", {
                count = #sessionsOrError,
            })
        end
    end)
end

addEvent(Events.DATABASE_READY, true)

if Schema.isMigrated() then
    -- Migration already finished by the time this file loaded (e.g. a
    -- resource-only restart of `core` after the very first boot, where
    -- every table already exists and CREATE TABLE IF NOT EXISTS/column
    -- diffing races nothing) - Events.DATABASE_READY already fired and
    -- would never reach a handler registered only now, so run directly.
    closeOrphanedSessions()
else
    addEventHandler(Events.DATABASE_READY, resourceRoot, closeOrphanedSessions)
end
