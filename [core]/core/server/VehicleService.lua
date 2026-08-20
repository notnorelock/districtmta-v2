-- Server-to-server bridge exposing VehicleRepository to gm_vehicles (a
-- separate resource) without ever handing a callback across the resource
-- boundary - see VehicleRepository.lua's own module comment and
-- docs/Architecture.md's "The one hard rule for extending the project".
-- Mirrors FetchBridge's requestId-correlated request/response shape:
-- gm_vehicles/server/VehicleBridge.lua triggers Events.VEHICLE_REPOSITORY_REQUEST
-- with { requestId, method, args }, this file runs the matching
-- VehicleRepository method locally (the callback closure never leaves
-- this resource) and triggers Events.VEHICLE_REPOSITORY_RESPONSE back
-- with { requestId, ok, result }.
VehicleService = VehicleService or {}

-- Whitelist, not a raw _G[method] lookup - a request's `method` field is
-- effectively attacker-controlled input from another resource's Lua (not
-- from a browser, but still not code this file should trust blindly);
-- only these exact repository methods are reachable this way.
local METHODS = {
    findById = VehicleRepository.findById,
    findByOwnerAccountId = VehicleRepository.findByOwnerAccountId,
    findAllPrivate = VehicleRepository.findAllPrivate,
    create = VehicleRepository.create,
    update = VehicleRepository.update,
    delete = VehicleRepository.delete,
}

addEvent(Events.VEHICLE_REPOSITORY_REQUEST, true)
addEventHandler(Events.VEHICLE_REPOSITORY_REQUEST, root, function(data)
    if type(data) ~= "table" or type(data.requestId) ~= "string" or type(data.method) ~= "string" then
        Logger.warn("VehicleService", "Malformed VEHICLE_REPOSITORY_REQUEST", { data = data })
        return
    end

    local method = METHODS[data.method]
    if not method then
        Logger.warn("VehicleService", "Unknown VehicleRepository method requested", { method = data.method })
        triggerEvent(Events.VEHICLE_REPOSITORY_RESPONSE, resourceRoot, data.requestId, false, "UNKNOWN_METHOD")
        return
    end

    local args = data.args or {}

    -- Every VehicleRepository method takes 1 or 2 positional arguments
    -- before its callback (id/accountId/attributes, or none for
    -- findAllPrivate) - args is always an array, positionally matching.
    local function respond(ok, result)
        triggerEvent(Events.VEHICLE_REPOSITORY_RESPONSE, resourceRoot, data.requestId, ok, result)
    end

    if #args == 0 then
        method(respond)
    elseif #args == 1 then
        method(args[1], respond)
    else
        method(args[1], args[2], respond)
    end
end)

-- Flat exported wrapper - gm_vehicles waits on this (or Events.DATABASE_READY)
-- before sending its first VEHICLE_REPOSITORY_REQUEST, same gotcha
-- documented in docs/DatabaseContract.md's "Migration" section (a fresh
-- table sorted late alphabetically can still be mid-CREATE TABLE when a
-- dependent resource's onResourceStart fires).
function schemaIsMigrated() return Schema.isMigrated() end
