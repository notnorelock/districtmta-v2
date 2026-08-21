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

-- Guards every addEventHandler registered against a custom event (any
-- event name not starting with "on" - MTA's own events are always
-- onSomething, our registry in core_shared/shared/Events.lua never is).
-- A legitimate call always has either a real connected player as `client`
-- (triggerServerEvent from a player) or `source == resourceRoot`
-- (triggerEvent from this resource's own server-side code, e.g.
-- Events.DATABASE_READY). Anything else - triggerEvent/triggerServerEvent/
-- triggerClientEvent reaching this handler from some other origin with
-- neither - is dropped before the real handler runs. Native MTA events
-- (onPlayerJoin, onResourceStart, onClientGUIClick, ...) are untouched:
-- their `source` is controlled by the engine, not by this project's code,
-- so wrapping them here would do nothing but risk misclassifying one.
--
-- "endpoint:*" is excluded on purpose: FetchBridge (core_ui) triggerEvents
-- these from ITS OWN resourceRoot, not core's, by design (see
-- AccountEndpoints.lua/FetchBridge.lua) - source == resourceRoot would
-- never hold here even for the legitimate call. Events.VEHICLE_REPOSITORY_REQUEST
-- ("core:vehicleRepositoryRequest") and Events.ITEM_REPOSITORY_REQUEST
-- ("core:itemRepositoryRequest") are excluded for the identical reason:
-- gm_vehicles/server/VehicleBridge.lua and gm_items/server/ItemBridge.lua
-- each trigger their own event from THEIR OWN resourceRoot, not core's -
-- see VehicleService.lua/ItemService.lua.
local _addEventHandler = addEventHandler
addEventHandler = function(event, attachedTo, handlerFunction, ...)
    if type(event) ~= "string" or event:sub(1, 2) == "on" or event:sub(1, 9) == "endpoint:" or event == "core:vehicleRepositoryRequest" or event == "core:itemRepositoryRequest" then
        return _addEventHandler(event, attachedTo, handlerFunction, ...)
    end

    local function guardedHandler(...)
        if isElement(client) or source == resourceRoot then
            return handlerFunction(...)
        end

        if source ~= resourceRoot then
            local __args = ''
            local __i = 1

            while true do
                local name, value = debug.getlocal(1, __i)
                if not name then break end

                if name ~= '__args' and name ~= '__i' then
                    __args = __args .. ('`%s`: `%s`\n'):format(name, inspect(value))
                end

                __i = __i + 1
            end

            __args = __args:sub(1, -2)

            if isElement(source) and getElementType(source) == "player" then
                kickPlayer(source, "Wykryto niedozwolone wywołanie zdarzenia serwera. Zgłoś to administracji serwera.")
                Logger.security("GlobalResources", ("Rejected forged custom event '%s' from player with wrong source (%s)\nArguments:\n%s"):format(event, tostring(source), __args), { event = event, source = source })
            else
                Logger.security("GlobalResources", ("Rejected forged custom event '%s' from non-player element (%s)"):format(event, tostring(source)), { event = event, source = source })
            end
        end

        Logger.security("GlobalResources", ("Rejected forged custom event '%s' with no sender to kick"):format(event), { event = event })
    end

    return _addEventHandler(event, attachedTo, guardedHandler, ...)
end

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
