-- The only path by which the CEF browser can trigger server-side logic.
-- Generic, domain-agnostic router: endpoint owners register metadata via
-- exports.core_ui:fetchBridgeRegisterMeta(name, meta), then handle the
-- request via addEventHandler("endpoint:<name>", root, function(requestId,
-- player, payload) ... end), and respond via
-- exports.core_ui:fetchBridgeRespond(requestId, {success = ..., data/error = ...}).
-- Plain data only crosses the resource boundary - MTA cannot pass a live
-- Lua function across exports/triggerEvent (CLuaArgument::Read nils out
-- LUA_TFUNCTION), so a closure-bearing ctx object isn't possible here.
-- registerMeta overwrites rather than errors on re-registration, since a
-- normal resource restart re-registers everything against an unmodified registry.

FetchBridge = FetchBridge or {}

local endpointMeta = {}         -- endpoint name -> { authenticated, rateLimit }
local pendingRequests = {}      -- requestId -> { player, endpoint, createdAt, responded }
local rateLimitState = {}       -- player -> endpoint -> { count, windowStartedAt }

local REQUEST_TIMEOUT_MS = 15000
local DEFAULT_RATE_LIMIT = { limit = 30, intervalMs = 10000 }
local MAX_PAYLOAD_ARGUMENTS = ValidationRules.MAX_ARGUMENT_COUNT

--- Registers metadata for a browser-reachable endpoint. Must be paired
--- with an addEventHandler("endpoint:<name>", root, handler) - see module comment.
-- @param name string dot.separated endpoint name, e.g. "account.current"
-- @param meta table { authenticated: boolean, rateLimit: table|nil }
FetchBridge.registerMeta = function(name, meta)
    assert(type(name) == "string" and #name > 0, "FetchBridge.registerMeta requires an endpoint name")

    endpointMeta[name] = {
        authenticated = (meta and meta.authenticated) == true,
        rateLimit = (meta and meta.rateLimit) or DEFAULT_RATE_LIMIT,
    }

    Logger.debug("FetchBridge", "Endpoint metadata registered", { endpoint = name })
end

--- Sends the final response for a pending request. Called by the
--- resource that owns the endpoint, from anywhere in its handler chain.
-- @param requestId string
-- @param response table { success: boolean, data: any } | { success: false, error: table }
FetchBridge.respond = function(requestId, response)
    Logger.debug("FetchBridge", "respond", { requestId = requestId, success = response and response.success })

    local request = pendingRequests[requestId]
    if not request then
        Logger.warn("FetchBridge", "respond called for unknown/expired request", { requestId = requestId })
        return
    end

    if request.responded then
        Logger.warn("FetchBridge", "Duplicate response suppressed", { requestId = requestId, endpoint = request.endpoint })
        return
    end

    request.responded = true
    pendingRequests[requestId] = nil

    if isElement(request.player) then
        triggerClientEvent(request.player, Events.UI_FETCH_RESPONSE, resourceRoot, requestId, response)
    end
end

local function isRateLimited(player, endpointName, rule)
    local playerState = rateLimitState[player]
    if not playerState then
        playerState = {}
        rateLimitState[player] = playerState
    end

    local now = getTickCount()
    local bucket = playerState[endpointName]

    if not bucket or (now - bucket.windowStartedAt) >= rule.intervalMs then
        playerState[endpointName] = { count = 1, windowStartedAt = now }
        return false
    end

    bucket.count = bucket.count + 1
    return bucket.count > rule.limit
end

local function validateEnvelope(data)
    if type(data) ~= "table" then
        return false, "Malformed request envelope"
    end

    if type(data.id) ~= "string" or #data.id == 0 or #data.id > 128 then
        return false, "Invalid request id"
    end

    if type(data.endpoint) ~= "string" or #data.endpoint == 0 or #data.endpoint > ValidationRules.MAX_ENDPOINT_LENGTH then
        return false, "Invalid endpoint name"
    end

    if data.arguments ~= nil and type(data.arguments) ~= "table" then
        return false, "arguments must be an array"
    end

    if data.arguments and #data.arguments > MAX_PAYLOAD_ARGUMENTS then
        return false, "Too many arguments"
    end

    return true
end

addEvent(Events.UI_FETCH_REQUEST, true)
addEventHandler(Events.UI_FETCH_REQUEST, root, function(data)
    local player = client
    Logger.debug("FetchBridge", "UI_FETCH_REQUEST received", {
        player = isElement(player) and getPlayerName(player) or "unknown",
        endpoint = type(data) == "table" and tostring(data.endpoint) or "n/a",
        id = type(data) == "table" and tostring(data.id) or "n/a",
    })

    local valid, reason = validateEnvelope(data)

    if not valid then
        Logger.warn("FetchBridge", "Envelope failed validation", { reason = reason })
        SecurityService.report(player, "INVALID_UI_REQUEST", { reason = reason })
        -- No valid id to correlate a response to - drop silently; browser-side timeout handles it.
        return
    end

    local requestId = data.id
    local endpointName = data.endpoint
    local meta = endpointMeta[endpointName]

    if not meta then
        Logger.warn("FetchBridge", "Unknown endpoint requested", { endpoint = endpointName })
        SecurityService.report(player, "UNKNOWN_ENDPOINT", { endpoint = endpointName })
        triggerClientEvent(player, Events.UI_FETCH_RESPONSE, resourceRoot, requestId, {
            success = false,
            error = { code = ErrorCodes.UNKNOWN_ENDPOINT },
        })
        return
    end

    if meta.authenticated and not PlayerService.isAuthenticated(player) then
        triggerClientEvent(player, Events.UI_FETCH_RESPONSE, resourceRoot, requestId, {
            success = false,
            error = { code = ErrorCodes.NOT_AUTHENTICATED },
        })
        return
    end

    if isRateLimited(player, endpointName, meta.rateLimit) then
        triggerClientEvent(player, Events.UI_FETCH_RESPONSE, resourceRoot, requestId, {
            success = false,
            error = { code = ErrorCodes.RATE_LIMITED },
        })
        return
    end

    pendingRequests[requestId] = {
        player = player,
        endpoint = endpointName,
        createdAt = getTickCount(),
        responded = false,
    }

    setTimer(function()
        local request = pendingRequests[requestId]
        if request and not request.responded then
            FetchBridge.respond(requestId, { success = false, error = { code = ErrorCodes.REQUEST_TIMEOUT } })
        end
    end, REQUEST_TIMEOUT_MS, 1)

    local payload = data.arguments and data.arguments[1] or nil

    triggerEvent("endpoint:" .. endpointName, resourceRoot, requestId, player, payload)
end)

local function cleanupPlayerRequests(player)
    for requestId, request in pairs(pendingRequests) do
        if request.player == player then
            pendingRequests[requestId] = nil
        end
    end
    rateLimitState[player] = nil
end

addEventHandler("onPlayerQuit", root, function()
    cleanupPlayerRequests(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    pendingRequests = {}
    rateLimitState = {}
end)

-- Flat exported wrappers.
function fetchBridgeRegisterMeta(name, meta) FetchBridge.registerMeta(name, meta) end
function fetchBridgeRespond(requestId, response) FetchBridge.respond(requestId, response) end
