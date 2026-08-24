-- Server-to-server bridge exposing LicenseRepository to gm_licenses (a
-- separate resource) without ever handing a callback across the
-- resource boundary - see VehicleService.lua's own module comment and
-- docs/Architecture.md's "The one hard rule for extending the project".
-- gm_licenses/server/LicenseBridge.lua triggers
-- Events.LICENSE_REPOSITORY_REQUEST with { requestId, method, args },
-- this file runs the matching LicenseRepository method locally (the
-- callback closure never leaves this resource) and triggers
-- Events.LICENSE_REPOSITORY_RESPONSE back with { requestId, ok, result }.
LicenseService = LicenseService or {}

-- Whitelist, not a raw _G[method] lookup - see VehicleService.lua's own
-- comment on why.
local METHODS = {
    findGrantsByAccountId = LicenseRepository.findGrantsByAccountId,
    createGrant = LicenseRepository.createGrant,
    findActiveSuspensions = LicenseRepository.findActiveSuspensions,
    createSuspension = LicenseRepository.createSuspension,
    revokeSuspension = LicenseRepository.revokeSuspension,
}

addEvent(Events.LICENSE_REPOSITORY_REQUEST, true)
addEventHandler(Events.LICENSE_REPOSITORY_REQUEST, root, function(data)
    if type(data) ~= "table" or type(data.requestId) ~= "string" or type(data.method) ~= "string" then
        Logger.warn("LicenseService", "Malformed LICENSE_REPOSITORY_REQUEST", { data = data })
        return
    end

    local method = METHODS[data.method]
    if not method then
        Logger.warn("LicenseService", "Unknown LicenseRepository method requested", { method = data.method })
        triggerEvent(Events.LICENSE_REPOSITORY_RESPONSE, resourceRoot, data.requestId, false, "UNKNOWN_METHOD")
        return
    end

    local args = data.args or {}

    -- LicenseRepository methods take 0-4 positional arguments before
    -- their callback (findActiveSuspensions takes 3: accountId,
    -- category, nowSql; createSuspension takes a single data table) -
    -- args is always an array, positionally matching.
    local function respond(ok, result)
        triggerEvent(Events.LICENSE_REPOSITORY_RESPONSE, resourceRoot, data.requestId, ok, result)
    end

    if #args == 0 then
        method(respond)
    elseif #args == 1 then
        method(args[1], respond)
    elseif #args == 2 then
        method(args[1], args[2], respond)
    elseif #args == 3 then
        method(args[1], args[2], args[3], respond)
    else
        method(args[1], args[2], args[3], args[4], respond)
    end
end)
