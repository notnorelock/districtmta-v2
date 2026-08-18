local registeredEndpoints = {}

local function registerEndpoint(name, meta, handler)
    registeredEndpoints[#registeredEndpoints + 1] = { name = name, meta = meta }

    addEvent("endpoint:" .. name, true)
    addEventHandler("endpoint:" .. name, root, handler)
end

local function registerAllWithCoreUi()
    for _, endpoint in ipairs(registeredEndpoints) do
        exports.core_ui:fetchBridgeRegisterMeta(endpoint.name, endpoint.meta)
    end
    outputServerLog(string.format("[INFO] [core_auth] Registered %d spawn endpoint(s) with core_ui", #registeredEndpoints))
end

registerEndpoint("spawn.list", {
    authenticated = true,
    rateLimit = { limit = 10, intervalMs = 10000 },
}, function(requestId, player, payload)
    exports.core_ui:fetchBridgeRespond(requestId, exports.core_shared:successResponse(SpawnLocations.toPublicList()))
end)

registerEndpoint("spawn.select", {
    authenticated = true,
    rateLimit = { limit = 10, intervalMs = 10000 },
}, function(requestId, player, payload)
    local spawnId = type(payload) == "table" and payload.id or nil

    if type(spawnId) ~= "string" then
        exports.core_ui:fetchBridgeRespond(requestId, exports.core_shared:errorResponse(ErrorCodes.INVALID_ARGUMENTS, "Expected an object with a spawn id"))
        return
    end

    local location = SpawnLocations.findById(spawnId)
    if not location then
        exports.core_ui:fetchBridgeRespond(requestId, exports.core_shared:errorResponse(ErrorCodes.INVALID_SPAWN, "Unknown spawn location"))
        return
    end

    exports.gm_roleplay:gameplayEnterWorld(player, location)
    triggerClientEvent(player, Events.SPAWN_SELECT_CLOSE, player)

    exports.core_ui:fetchBridgeRespond(requestId, exports.core_shared:successResponse({ id = location.id }))
end)

local function isCoreUiRunning()
    local resource = getResourceFromName("core_ui")
    return resource ~= nil and getResourceState(resource) == "running"
end

if isCoreUiRunning() then
    registerAllWithCoreUi()
end

addEventHandler("onResourceStart", root, function(resource)
    if getResourceName(resource) == "core_ui" then
        registerAllWithCoreUi()
    end
end)
