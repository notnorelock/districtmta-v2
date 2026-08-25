-- Server-to-server bridge exposing SettingsRepository to gm_settings (a
-- separate resource) without ever handing a callback across the
-- resource boundary - see LicenseService.lua's own module comment and
-- docs/Architecture.md's "The one hard rule for extending the project".
-- gm_settings/server/SettingsBridge.lua triggers
-- Events.SETTINGS_REPOSITORY_REQUEST with { requestId, method, args },
-- this file runs the matching SettingsRepository method locally (the
-- callback closure never leaves this resource) and triggers
-- Events.SETTINGS_REPOSITORY_RESPONSE back with { requestId, ok, result }.
SettingsService = SettingsService or {}

-- Whitelist, not a raw _G[method] lookup - see LicenseService.lua's own
-- comment on why.
local METHODS = {
    findByAccountId = SettingsRepository.findByAccountId,
    upsert = SettingsRepository.upsert,
}

addEvent(Events.SETTINGS_REPOSITORY_REQUEST, true)
addEventHandler(Events.SETTINGS_REPOSITORY_REQUEST, root, function(data)
    if type(data) ~= "table" or type(data.requestId) ~= "string" or type(data.method) ~= "string" then
        Logger.warn("SettingsService", "Malformed SETTINGS_REPOSITORY_REQUEST", { data = data })
        return
    end

    local method = METHODS[data.method]
    if not method then
        Logger.warn("SettingsService", "Unknown SettingsRepository method requested", { method = data.method })
        triggerEvent(Events.SETTINGS_REPOSITORY_RESPONSE, resourceRoot, data.requestId, false, "UNKNOWN_METHOD")
        return
    end

    local args = data.args or {}

    -- SettingsRepository methods take 1-2 positional arguments before
    -- their callback (findByAccountId takes accountId; upsert takes
    -- accountId, enabledIds) - args is always an array, positionally matching.
    local function respond(ok, result)
        triggerEvent(Events.SETTINGS_REPOSITORY_RESPONSE, resourceRoot, data.requestId, ok, result)
    end

    if #args == 0 then
        method(respond)
    elseif #args == 1 then
        method(args[1], respond)
    else
        method(args[1], args[2], respond)
    end
end)
