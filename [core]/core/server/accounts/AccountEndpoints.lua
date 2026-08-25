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
    Logger.info("AccountEndpoints", "Registered endpoints with core_ui", { count = #registeredEndpoints })
end

local successResponse = function(data) return exports.core_shared:successResponse(data) end
local errorResponse = function(code, message) return exports.core_shared:errorResponse(code, message) end

registerEndpoint("auth.status", {
    authenticated = false,
    rateLimit = { limit = 10, intervalMs = 10000 },
}, function(requestId, player, payload)
    local account = PlayerService.getAccount(player)
    exports.core_ui:fetchBridgeRespond(requestId, successResponse({
        authenticated = account ~= nil,
        account = account and AccountService.toPublic(account) or nil,
    }))
end)

registerEndpoint("auth.register", {
    authenticated = false,
    rateLimit = { limit = 5, intervalMs = 30000 },
}, function(requestId, player, payload)
    if type(payload) ~= "table" then
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(ErrorCodes.INVALID_ARGUMENTS, "Expected an object with login, email and password"))
        return
    end

    local mtaSerial = getPlayerSerial(player)

    AccountService.register(mtaSerial, payload, function(account)
        AccountService.resolveForPlayer(player, account.id, function(resolvedAccount)
            exports.core_ui:fetchBridgeRespond(requestId, successResponse(AccountService.toPublic(resolvedAccount)))
        end, function(code, message)
            exports.core_ui:fetchBridgeRespond(requestId, errorResponse(code, message))
        end)
    end, function(code, message)
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(code, message))
    end)
end)

registerEndpoint("auth.login", {
    authenticated = false,
    rateLimit = { limit = 10, intervalMs = 30000 },
}, function(requestId, player, payload)
    if type(payload) ~= "table" then
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(ErrorCodes.INVALID_ARGUMENTS, "Expected an object with login and password"))
        return
    end

    local mtaSerial = getPlayerSerial(player)

    AccountService.login(mtaSerial, payload, function(account)
        AccountService.resolveForPlayer(player, account.id, function(resolvedAccount)
            exports.core_ui:fetchBridgeRespond(requestId, successResponse(AccountService.toPublic(resolvedAccount)))
        end, function(code, message)
            exports.core_ui:fetchBridgeRespond(requestId, errorResponse(code, message))
        end)
    end, function(code, message)
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(code, message))
    end)
end)

registerEndpoint("account.current", {
    authenticated = true,
    rateLimit = { limit = 20, intervalMs = 10000 },
}, function(requestId, player, payload)
    local account = PlayerService.getAccount(player)

    if not account then
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(ErrorCodes.NOT_AUTHENTICATED))
        return
    end

    exports.core_ui:fetchBridgeRespond(requestId, successResponse(AccountService.toPublic(account)))
end)

registerEndpoint("account.changePassword", {
    authenticated = true,
    -- Tighter than account.current's 20/10s (a read) - this is an
    -- irreversible, security-sensitive mutation.
    rateLimit = { limit = 3, intervalMs = 60000 },
}, function(requestId, player, payload)
    if type(payload) ~= "table" then
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(ErrorCodes.INVALID_ARGUMENTS, "Expected an object with currentPassword and newPassword"))
        return
    end

    AccountService.changePassword(player, payload, function()
        -- Native toast lives HERE, not inside AccountService -
        -- AccountService methods stay notification-agnostic pure
        -- business logic (register/login never call NotificationService
        -- themselves either).
        NotificationService.send(player, {
            type = "success",
            title = "Hasło zmienione",
            message = "Twoje hasło zostało zmienione pomyślnie",
        })
        exports.core_ui:fetchBridgeRespond(requestId, successResponse({ ok = true }))
    end, function(code, message)
        exports.core_ui:fetchBridgeRespond(requestId, errorResponse(code, message))
    end)
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
