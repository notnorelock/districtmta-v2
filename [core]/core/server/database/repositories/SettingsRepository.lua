-- Thin facade over the PlayerSetting Active Record model - gm_settings'
-- SettingsBridge calls this, never PlayerSetting/Model/QueryBuilder
-- directly. Also owns the toJSON/fromJSON boundary for the "enabled"
-- text column (see PlayerSetting.lua's own module comment) - every row
-- this repository hands back has "enabled" already decoded into a real
-- Lua array; every write here JSON-encodes it before it reaches the
-- database. Callers above this file never see a JSON string.
SettingsRepository = SettingsRepository or {}

--- @param row table|nil a PlayerSetting instance (or plain row) - mutated in place
-- @return table|nil the same table, for chaining
local function decodeEnabled(row)
    if not row then
        return row
    end
    if type(row.enabled) == "string" then
        row.enabled = fromJSON(row.enabled) or {}
    end
    return row
end

--- @param accountId number
-- @param callback function(ok: boolean, rowOrNilOrError: table|nil|string) -
--        rowOrNilOrError is nil (ok=true) if the account has no row yet,
--        same "empty result is not an error" convention as
--        ItemRepository.findOwnerless.
SettingsRepository.findByAccountId = function(accountId, callback)
    PlayerSetting:query():where("account_id", accountId):first(function(ok, row)
        callback(ok, ok and decodeEnabled(row) or row)
    end)
end

--- Creates the account's player_settings row on first toggle, otherwise
--- whole-array-replaces "enabled" in place (never a partial patch) -
--- same "replace the entire list" shape GROUP_SET_VEHICLE_RANKS already
--- uses for a per-account allowlist.
-- @param accountId number
-- @param enabledIds table array of setting-toggle id strings
-- @param callback function(ok: boolean, rowOrError: table|string)
SettingsRepository.upsert = function(accountId, enabledIds, callback)
    SettingsRepository.findByAccountId(accountId, function(ok, existing)
        if not ok then
            callback(false, existing)
            return
        end

        local encoded = toJSON(enabledIds or {})
        if existing then
            PlayerSetting:query():where("id", existing.id):update({ enabled = encoded }, function(updateOk, affectedOrError)
                if not updateOk then
                    callback(false, affectedOrError)
                    return
                end
                existing.enabled = enabledIds or {}
                callback(true, existing)
            end)
        else
            PlayerSetting:create({ account_id = accountId, enabled = encoded }, function(createOk, row)
                callback(createOk, createOk and decodeEnabled(row) or row)
            end)
        end
    end)
end

-- Deliberately NO flat exported wrappers here - see ItemRepository.lua's
-- own closing comment / docs/Architecture.md's "one hard rule": a
-- callback must never cross a resource boundary. gm_settings (a
-- separate resource) reaches this repository through
-- core/server/SettingsService.lua's event-based request/response
-- bridge instead.
