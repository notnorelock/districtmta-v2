-- Must be the first server script loaded in meta.xml - see
-- docs/Architecture.md's "The GlobalResources.lua pattern".

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

local ValidationRules = setmetatable({
    isValidLogin = function(login) return exports.core_shared:validationRulesIsValidLogin(login) end,
    isValidEmail = function(email) return exports.core_shared:validationRulesIsValidEmail(email) end,
    normalizeLogin = function(login) return exports.core_shared:validationRulesNormalizeLogin(login) end,
    normalizeEmail = function(email) return exports.core_shared:validationRulesNormalizeEmail(email) end,
    isValidPassword = function(password) return exports.core_shared:validationRulesIsValidPassword(password) end,
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

local ElementData = setmetatable({
    accountField = function(field) return exports.core_shared:elementDataAccountField(field) end,
}, {
    __index = function(table, key)
        if cachedTables.ElementData == nil then
            if not isResourceAvailable("core_shared") then
                return nil
            end
            cachedTables.ElementData = exports.core_shared:getElementData()
        end
        return cachedTables.ElementData[key]
    end,
})

local PushService = {
    send = function(player, event, data) exports.core_ui:pushServiceSend(player, event, data) end,
    broadcast = function(event, data) exports.core_ui:pushServiceBroadcast(event, data) end,
}

setmetatable(_G, {
    __index = function(table, key)
        if key == "ValidationRules" then
            return isResourceAvailable("core_shared") and ValidationRules or false
        end

        if key == "ElementData" then
            return isResourceAvailable("core_shared") and ElementData or false
        end

        if key == "PushService" then
            return isResourceAvailable("core_ui") and PushService or false
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
