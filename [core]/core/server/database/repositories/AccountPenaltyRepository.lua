-- Thin facade over the AccountPenalty Active Record model.
AccountPenaltyRepository = AccountPenaltyRepository or {}

--- @param data table { accountId, mtaSerial, type, reason, issuedByAccountId, expiresAt } - all but accountId/type may be nil
-- @param callback function(ok: boolean, penaltyOrError: table|string)
AccountPenaltyRepository.create = function(data, callback)
    AccountPenalty:create({
        account_id = data.accountId,
        mta_serial = data.mtaSerial,
        type = data.type,
        reason = data.reason,
        issued_by_account_id = data.issuedByAccountId,
        expires_at = data.expiresAt,
    }, callback)
end

--- @param id number
-- @param callback function(ok: boolean, penaltyOrError: table|nil|string)
AccountPenaltyRepository.findById = function(id, callback)
    AccountPenalty:find(id, callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, penaltiesOrError: table|string)
AccountPenaltyRepository.findByAccountId = function(accountId, callback)
    AccountPenalty:where("account_id", accountId):orderBy("created_at", "DESC"):get(callback)
end

--- Returns every active (not revoked, not naturally expired) row of a
--- given type, not just the first match, so a caller can pick the
--- longest-lasting one if more than one is somehow active.
-- @param accountId number
-- @param penaltyType string one of Enums.PenaltyType's values
-- @param nowSql string current UTC time, "YYYY-MM-DD HH:MM:SS"
-- @param callback function(ok: boolean, rowsOrError: table|string)
AccountPenaltyRepository.findActiveByType = function(accountId, penaltyType, nowSql, callback)
    AccountPenalty:where("account_id", accountId)
        :where("type", penaltyType)
        :where("revoked_at", "IS", Model.NULL)
        :get(function(ok, rows)
            if not ok then
                callback(false, rows)
                return
            end

            local active = {}
            for _, row in ipairs(rows) do
                if row.expires_at == nil or row.expires_at > nowSql then
                    active[#active + 1] = row
                end
            end
            callback(true, active)
        end)
end

--- @param accountId number
-- @param nowSql string see findActiveByType
-- @param callback function(ok: boolean, banRowsOrError: table|string)
AccountPenaltyRepository.findActiveBans = function(accountId, nowSql, callback)
    AccountPenaltyRepository.findActiveByType(accountId, Enums.PenaltyType.BAN, nowSql, callback)
end

--- @param accountId number
-- @param nowSql string see findActiveByType
-- @param callback function(ok: boolean, muteRowsOrError: table|string)
AccountPenaltyRepository.findActiveMutes = function(accountId, nowSql, callback)
    AccountPenaltyRepository.findActiveByType(accountId, Enums.PenaltyType.MUTE, nowSql, callback)
end

--- Counts penalties issued BY an admin account (issued_by_account_id, not account_id).
-- @param issuedByAccountId number
-- @param callback function(ok: boolean, countOrError: number|string)
AccountPenaltyRepository.countIssuedByAccountId = function(issuedByAccountId, callback)
    AccountPenalty:where("issued_by_account_id", issuedByAccountId):count(callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
AccountPenaltyRepository.revoke = function(id, callback)
    AccountPenalty:query():where("id", id):update({
        revoked_at = os.date("!%Y-%m-%d %H:%M:%S"),
    }, callback)
end
