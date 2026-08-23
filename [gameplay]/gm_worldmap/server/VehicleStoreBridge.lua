-- Server-side bridge to core's VehicleStoreRepository, same shape as
-- gm_vehicles/server/VehicleBridge.lua - a callback can never cross the
-- resource boundary directly (see docs/Architecture.md's "The one hard
-- rule for extending the project"), so this correlates requestIds
-- against core's existing VEHICLE_REPOSITORY_REQUEST/_RESPONSE bridge
-- (already whitelists findAllVehicleStores, see core/server/VehicleService.lua's
-- METHODS table) rather than adding a second one.
VehicleStoreBridge = VehicleStoreBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param callback function(ok: boolean, storesOrError: table|string)
VehicleStoreBridge.findAll = function(callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_worldmap:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.VEHICLE_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = "findAllVehicleStores",
        args = {},
    })
end

addEvent(Events.VEHICLE_REPOSITORY_RESPONSE, true)
addEventHandler(Events.VEHICLE_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
    local callback = pendingCallbacks[requestId]
    if not callback then
        -- Not ours (another resource's own pending request sharing the
        -- same broadcast event) or already answered - not an error.
        return
    end

    pendingCallbacks[requestId] = nil
    callback(ok, result)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    pendingCallbacks = {}
end)
