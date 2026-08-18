-- Thin facade over the AdminDutySession Active Record model.
AdminDutySessionRepository = AdminDutySessionRepository or {}

--- @param accountId number
-- @param callback function(ok: boolean, sessionOrError: table|string)
AdminDutySessionRepository.start = function(accountId, callback)
    AdminDutySession:create({ account_id = accountId }, callback)
end

--- @param sessionId number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AdminDutySessionRepository.finish = function(sessionId, callback)
    AdminDutySession:query():where("id", sessionId):update({
        ended_at = os.date("!%Y-%m-%d %H:%M:%S"),
    }, callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, sessionsOrError: table|string)
AdminDutySessionRepository.findByAccountId = function(accountId, callback)
    AdminDutySession:where("account_id", accountId):orderBy("started_at", "ASC"):get(callback)
end

--- @param callback function(ok: boolean, sessionsOrError: table|string)
AdminDutySessionRepository.findOpen = function(callback)
    AdminDutySession:where("ended_at", "IS", Model.NULL):get(callback)
end
