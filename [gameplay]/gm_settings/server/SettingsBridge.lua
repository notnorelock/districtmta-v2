-- Bridge to core's SettingsRepository, same requestId-correlated
-- request/response shape as gm_licenses/server/LicenseBridge.lua -
-- method is one of core/server/SettingsService.lua's whitelisted
-- method names.
SettingsBridge = SettingsBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

SettingsBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_settings:settings:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.SETTINGS_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = method,
        args = args or {},
    })
end

addEvent(Events.SETTINGS_REPOSITORY_RESPONSE, true)
addEventHandler(Events.SETTINGS_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
    local callback = pendingCallbacks[requestId]
    if not callback then
        return
    end

    pendingCallbacks[requestId] = nil
    callback(ok, result)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    pendingCallbacks = {}
end)
