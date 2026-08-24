-- Thin facade over the LicenseGrant/LicenseSuspension Active Record
-- models, mirroring AccountPenaltyRepository.lua's shape (including its
-- findActiveByType idiom: fetch non-revoked rows, filter expiry in Lua).
LicenseRepository = LicenseRepository or {}

--- @param accountId number
-- @param callback function(ok: boolean, rowsOrError: table|string)
LicenseRepository.findGrantsByAccountId = function(accountId, callback)
    LicenseGrant:where("account_id", accountId):get(callback)
end

--- @param accountId number
-- @param category string one of Enums.LicenseCategory
-- @param callback function(ok: boolean, rowOrError: table|string)
LicenseRepository.createGrant = function(accountId, category, callback)
    LicenseGrant:create({ account_id = accountId, category = category }, callback)
end

--- Returns every active (not revoked, not naturally expired) suspension
--- row for this account+category, not just the first match.
-- @param accountId number
-- @param category string one of Enums.LicenseCategory
-- @param nowSql string current UTC time, "YYYY-MM-DD HH:MM:SS"
-- @param callback function(ok: boolean, activeRowsOrError: table|string)
LicenseRepository.findActiveSuspensions = function(accountId, category, nowSql, callback)
    LicenseSuspension:where("account_id", accountId)
        :where("category", category)
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

--- @param data table { accountId, category, reason, issuedByAccountId, expiresAt }
-- @param callback function(ok: boolean, rowOrError: table|string)
LicenseRepository.createSuspension = function(data, callback)
    LicenseSuspension:create({
        account_id = data.accountId,
        category = data.category,
        reason = data.reason,
        issued_by_account_id = data.issuedByAccountId,
        expires_at = data.expiresAt,
    }, callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
LicenseRepository.revokeSuspension = function(id, callback)
    LicenseSuspension:query():where("id", id):update({
        revoked_at = os.date("!%Y-%m-%d %H:%M:%S"),
    }, callback)
end
