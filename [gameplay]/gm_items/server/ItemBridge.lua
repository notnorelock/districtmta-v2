-- Client side of the request/response bridge to core's ItemRepository
-- (see core/server/ItemService.lua's module comment) - the only way
-- ItemService.lua (this resource) talks to the database, since a
-- callback can never cross the resource boundary directly (see
-- docs/Architecture.md's "The one hard rule for extending the project").
-- Every ItemRepository.* call in this resource goes through
-- ItemBridge.call, never a raw triggerEvent/exports.core: call. Mirrors
-- gm_vehicles/server/VehicleBridge.lua exactly.
ItemBridge = ItemBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param method string one of core/server/ItemService.lua's whitelisted method names
-- @param args table|nil positional arguments, matching ItemRepository's
--        own signature minus the trailing callback (e.g. { id } for
--        findById, {} or nil for findOwnerless)
-- @param callback function(ok: boolean, resultOrError: any)
ItemBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_items:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.ITEM_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = method,
        args = args or {},
    })
end

addEvent(Events.ITEM_REPOSITORY_RESPONSE, true)
addEventHandler(Events.ITEM_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
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
