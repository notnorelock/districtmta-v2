-- Bridge to core's LicenseRepository, same requestId-correlated
-- request/response shape as gm_groups/server/GroupVehicleBridge.lua.
LicenseBridge = LicenseBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param method string one of core/server/LicenseService.lua's whitelisted method names
-- @param args table|nil positional arguments
-- @param callback function(ok: boolean, resultOrError: any)
LicenseBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_licenses:license:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.LICENSE_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = method,
        args = args or {},
    })
end

addEvent(Events.LICENSE_REPOSITORY_RESPONSE, true)
addEventHandler(Events.LICENSE_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
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
