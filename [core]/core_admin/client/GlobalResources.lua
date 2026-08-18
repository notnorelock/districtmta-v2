-- Resolves Events/Enums from core_shared via the lazy-metatable pattern
-- used across this project. No UI/PlayerService/Permissions proxy - this
-- is a native dxGUI/dxDraw window, and every permission check happens
-- server-side. Must be the first client script loaded in meta.xml.

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

setmetatable(_G, {
    __index = function(table, key)
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
