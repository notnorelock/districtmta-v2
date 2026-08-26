-- Proxies Events/ErrorCodes/Enums/ValidationRules/PlayerService/
-- SecurityService from core_shared/core via the lazy-metatable pattern
-- used across this project. Must be the first server script loaded.
--
-- Logger is deliberately NOT proxied here (see Logger.lua) - a Logger
-- call re-entering core via exports while core_ui was itself entered
-- FROM core (e.g. AccountEndpoints.lua -> Logger.debug -> back into
-- core) is a re-entrant cross-resource export call that reliably broke
-- this proxy; core_ui keeps its own small local Logger copy instead.

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
    ErrorCodes = { resource = "core_shared", getter = "getErrorCodes" },
    Enums = { resource = "core_shared", getter = "getEnums" },
}
local cachedTables = {}

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

local ValidationRules = setmetatable({
    isValidLogin = function(login) return exports.core_shared:validationRulesIsValidLogin(login) end,
    isValidEmail = function(email) return exports.core_shared:validationRulesIsValidEmail(email) end,
    normalizeLogin = function(login) return exports.core_shared:validationRulesNormalizeLogin(login) end,
    normalizeEmail = function(email) return exports.core_shared:validationRulesNormalizeEmail(email) end,
}, {
    __index = function(table, key)
        if cachedTables.ValidationRules == nil then
            if not isResourceAvailable("core_shared") then
                return nil
            end
            cachedTables.ValidationRules = exports.core_shared:getValidationRules()
        end
        return cachedTables.ValidationRules[key]
    end,
})

local PlayerService = {
    isAuthenticated = function(player) return exports.core:playerServiceIsAuthenticated(player) end,
}

local SecurityService = {
    report = function(player, code, metadata) exports.core:securityServiceReport(player, code, metadata) end,
}

local LOCAL_PROXY_MAP = {
    PlayerService = PlayerService,
    SecurityService = SecurityService,
}

setmetatable(_G, {
    __index = function(table, key)
        if key == "ValidationRules" then
            return isResourceAvailable("core_shared") and ValidationRules or false
        end

        if key == "ElementData" then
            return isResourceAvailable("core_shared") and ElementData or false
        end

        local proxy = LOCAL_PROXY_MAP[key]
        if proxy then
            return isResourceAvailable("core") and proxy or false
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
