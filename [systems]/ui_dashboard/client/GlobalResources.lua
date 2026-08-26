-- Resolves Events/Enums/ElementData from core_shared via the lazy-
-- metatable pattern used across this project. Must be the first client
-- script loaded in meta.xml.

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
        
        if key == "ElementData" then
            return isResourceAvailable("core_shared") and ElementData or false
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
