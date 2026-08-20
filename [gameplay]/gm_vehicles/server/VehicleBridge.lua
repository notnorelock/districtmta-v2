-- Client side of the request/response bridge to core's VehicleRepository
-- (see core/server/database/VehicleService.lua's module comment) - the
-- only way VehicleService.lua (this resource) talks to the database,
-- since a callback can never cross the resource boundary directly (see
-- docs/Architecture.md's "The one hard rule for extending the project").
-- Every VehicleRepository.* call in this resource goes through
-- VehicleBridge.call, never a raw triggerEvent/exports.core: call.
VehicleBridge = VehicleBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param method string one of VehicleService.lua's whitelisted method names
-- @param args table|nil positional arguments, matching VehicleRepository's
--        own signature minus the trailing callback (e.g. { id } for
--        findById, {} or nil for findAllPrivate)
-- @param callback function(ok: boolean, resultOrError: any)
VehicleBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_vehicles:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.VEHICLE_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = method,
        args = args or {},
    })
end

addEvent(Events.VEHICLE_REPOSITORY_RESPONSE, true)
addEventHandler(Events.VEHICLE_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
    local callback = pendingCallbacks[requestId]
    if not callback then
        -- Already answered, or this resource restarted mid-flight and
        -- lost its own pending table - not an error, just nothing to do.
        return
    end

    pendingCallbacks[requestId] = nil
    callback(ok, result)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    pendingCallbacks = {}
end)
