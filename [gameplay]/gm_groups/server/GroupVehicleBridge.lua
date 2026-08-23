-- Bridge to core's VehicleRepository/GroupVehicleRankRepository, reusing
-- the SAME Events.VEHICLE_REPOSITORY_REQUEST/_RESPONSE channel
-- gm_vehicles/server/VehicleBridge.lua already talks to (core/server/
-- VehicleService.lua's own addEventHandler is registered on `root`, so
-- ANY resource triggering that event gets answered, not just gm_vehicles -
-- the request/args/callback shape is identical, this is just a second
-- caller of the same bridge). Used for the group-vehicle-adjacent
-- repository methods only (find*/create/update for group-purpose
-- vehicles, findVehicleRanksByVehicleId/setVehicleRanks/
-- deleteVehicleRanksByVehicleId) - gm_groups has no reason to duplicate
-- VehicleBridge.lua wholesale for the handful of calls it actually needs.
GroupVehicleBridge = GroupVehicleBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param method string one of core/server/VehicleService.lua's whitelisted method names
-- @param args table|nil positional arguments
-- @param callback function(ok: boolean, resultOrError: any)
GroupVehicleBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_groups:vehicle:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

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
        -- Not one of ours (gm_vehicles' own VehicleBridge.lua uses this
        -- same broadcast response event with its own requestId prefix),
        -- or already answered - not an error, just nothing to do.
        return
    end

    pendingCallbacks[requestId] = nil
    callback(ok, result)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    pendingCallbacks = {}
end)
