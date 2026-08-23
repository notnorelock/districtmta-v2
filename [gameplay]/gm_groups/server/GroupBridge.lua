-- Server side of the request/response bridge to core's GroupRepository/
-- GroupRankRepository/GroupMemberRepository (see core/server/GroupService.lua's
-- module comment) - the only way this resource talks to the database,
-- since a callback can never cross the resource boundary directly (see
-- docs/Architecture.md's "The one hard rule for extending the project").
-- Every group-repository call in this resource goes through
-- GroupBridge.call, never a raw triggerEvent/exports.core: call. Mirrors
-- gm_vehicles/server/VehicleBridge.lua exactly.
GroupBridge = GroupBridge or {}

local nextRequestId = 0
local pendingCallbacks = {}

--- @param method string one of GroupService.lua's whitelisted method names
-- @param args table|nil positional arguments, matching the target
--        repository method's own signature minus the trailing callback
-- @param callback function(ok: boolean, resultOrError: any)
GroupBridge.call = function(method, args, callback)
    nextRequestId = nextRequestId + 1
    local requestId = "gm_groups:" .. tostring(nextRequestId) .. ":" .. tostring(getTickCount())

    pendingCallbacks[requestId] = callback

    triggerEvent(Events.GROUP_REPOSITORY_REQUEST, resourceRoot, {
        requestId = requestId,
        method = method,
        args = args or {},
    })
end

addEvent(Events.GROUP_REPOSITORY_RESPONSE, true)
addEventHandler(Events.GROUP_REPOSITORY_RESPONSE, root, function(requestId, ok, result)
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
