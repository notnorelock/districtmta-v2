-- Client-side counterpart of server/GlobalResources.lua. ValidationRules
-- is special-cased below since MTA's exports mechanism strips function
-- fields from returned tables, so its methods need their own flat exports.
-- Must be the first client script loaded in meta.xml.

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

setmetatable(_G, {
    __index = function(table, key)
        if key == "ValidationRules" then
            return isResourceAvailable("core_shared") and ValidationRules or false
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
