-- World interaction (E, held) - server side. Owns the actual range/type
-- re-validation and interaction execution; WorldInteractionState.lua
-- (client) only decides which nearby element to ASK about (closest to
-- screen center, see its own module comment) and never assumes an
-- interaction is actually allowed just because the client thinks it looks
-- reasonable - both INTERACTION_REQUEST_LIST and INTERACTION_CALL below
-- redo the distance/type checks against server-authoritative element
-- state, same pattern as VehicleInteractionService.lua's own re-validation
-- of "is this player actually the driver".
InteractionService = InteractionService or {}

-- Fixed per-type ranges - the original reference implementation scaled
-- object/vehicle ranges off the element's own radius via getElementRadius,
-- which doesn't exist in MTA (there is no generic "how big is this
-- element" native); a fixed distance per type is close enough for an
-- interaction-range check and doesn't need one.
local PLAYER_RANGE = 3
local OBJECT_RANGE = 5
local VEHICLE_RANGE = 8

--- @param player element
-- @param element element
-- @return boolean true if `element` is within interaction range of `player`
local function inRange(player, element)
    local px, py, pz = getElementPosition(player)
    local ex, ey, ez = getElementPosition(element)
    local dist = getDistanceBetweenPoints3D(px, py, pz, ex, ey, ez)

    local elementType = getElementType(element)
    if elementType == "player" then
        return dist < PLAYER_RANGE
    elseif elementType == "object" then
        return dist < OBJECT_RANGE
    elseif elementType == "vehicle" then
        return dist < VEHICLE_RANGE
    end

    return false
end

--- @param player element
-- @param element element
-- @return table[] { key, label, icon }[] - every interaction currently
--         allowed on `element` for `player`, [] if out of range or none apply
local function listFor(player, element)
    if not isElement(element) or not inRange(player, element) then
        return {}
    end

    local items = {}
    for _, key in ipairs(InteractionRegistry.availableFor(player, element)) do
        local definition = InteractionRegistry.get(key)
        items[#items + 1] = { key = key, label = definition.label, icon = definition.icon }
    end
    return items
end

addEvent(Events.INTERACTION_REQUEST_LIST, true)
addEventHandler(Events.INTERACTION_REQUEST_LIST, root, function(element)
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end

    triggerClientEvent(client, Events.INTERACTION_LIST_RECEIVED, client, listFor(client, element))
end)

addEvent(Events.INTERACTION_CALL, true)
addEventHandler(Events.INTERACTION_CALL, root, function(element, key)
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end

    if not isElement(element) or not inRange(client, element) then
        return
    end

    if not InteractionRegistry.isAllowed(client, key, element) then
        Logger.security("InteractionService", "Rejected disallowed interaction call", {
            player = getPlayerName(client),
            key = key,
        })
        return
    end

    local definition = InteractionRegistry.get(key)
    local ok, err = pcall(definition.handler, client, element)
    if not ok then
        Logger.error("InteractionService", "Interaction handler threw", { key = key, error = tostring(err) })
    end
end)
