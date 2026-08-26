-- Lazy-metatable proxy for Events/Enums/Logger/PlayerService/
-- NotificationService from core - see gm_licenses/server/GlobalResources.lua
-- for the same pattern. Must be the first server script loaded in meta.xml.

local function isResourceAvailable(resourceName)
    local resource = getResourceFromName(resourceName)
    if not resource then
        return false
    end

    local state = getResourceState(resource)
    return state == "running" or state == "loaded"
end

local TABLE_RESOURCE_MAP = {
    Events = { resource = "core_shared", getter = "getEvents" },
    Enums = { resource = "core_shared", getter = "getEnums" },
}
local cachedTables = {}

local PlayerService = {
    isAuthenticated = function(player) return exports.core:playerServiceIsAuthenticated(player) end,
    getAccountId = function(player) return exports.core:playerServiceGetAccountId(player) end,
    getRole = function(player) return exports.core:playerServiceGetRole(player) end,
    getMoney = function(player) return exports.core:playerServiceGetMoney(player) end,
}

local Logger = {
    debug = function(scope, message, context) exports.core:loggerDebug(scope, message, context) end,
    info = function(scope, message, context) exports.core:loggerInfo(scope, message, context) end,
    warn = function(scope, message, context) exports.core:loggerWarn(scope, message, context) end,
    error = function(scope, message, context) exports.core:loggerError(scope, message, context) end,
    security = function(scope, message, context) exports.core:loggerSecurity(scope, message, context) end,
}

local NotificationService = {
    send = function(player, notification) exports.core:notificationServiceSend(player, notification) end,
    broadcast = function(notification) exports.core:notificationServiceBroadcast(notification) end,
}

local ElementData = setmetatable({
    accountField = function(field) return exports.core_shared:elementDataAccountField(field) end,
}, {
    __index = function(table, key)
        if cachedTables.ElementData == nil then
            if not isResourceAvailable("core_shared") then
                return nil
            end
            cachedTables.ElementData = exports.core_shared:getElementDatas()
        end
        return cachedTables.ElementData[key]
    end,
})

setmetatable(_G, {
    __index = function(table, key)
        if key == "ElementData" then
            return isResourceAvailable("core_shared") and ElementData or false
        end

        if key == "PlayerService" then
            return isResourceAvailable("core") and PlayerService or false
        end
        if key == "NotificationService" then
            return isResourceAvailable("core") and NotificationService or false
        end
        if key == "Logger" then
            return isResourceAvailable("core") and Logger or false
        end

        local tableSpec = TABLE_RESOURCE_MAP[key]
        if tableSpec then
            if cachedTables[key] == nil then
                if not isResourceAvailable(tableSpec.resource) then
                    return false
                end
                cachedTables[key] = exports[tableSpec.resource][tableSpec.getter](exports[tableSpec.resource])
            end
            return cachedTables[key]
        end

        return rawget(table, key)
    end,
})
