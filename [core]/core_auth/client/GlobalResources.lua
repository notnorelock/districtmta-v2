-- Resolves Events/Enums from core_shared, and UI from core_ui, via the
-- lazy-metatable pattern used across this project. Logger is NOT proxied
-- here - a local copy instead (see Logger.lua): this resource's
-- CredentialTransport.lua is entered FROM core_ui, so a Logger call
-- reaching back into core via exports mid-callstack would be a re-entrant
-- cross-resource export chain, same failure mode core_ui/server/GlobalResources.lua avoids.
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
    Enums = { resource = "core_shared", getter = "getEnums" },
}
local cachedTables = {}

local UI = {
    open = function(windowName, blocking) exports.core_ui:uiOpen(windowName, blocking) end,
    close = function(windowName) exports.core_ui:uiClose(windowName) end,
    isOpen = function(windowName) return exports.core_ui:uiIsOpen(windowName) end,
    isReady = function() return exports.core_ui:uiIsReady() end,
}

setmetatable(_G, {
    __index = function(table, key)
        if key == "UI" then
            return isResourceAvailable("core_ui") and UI or false
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
