-- sprawdzanie gracza czy zalogowany itd.

local IS_CLIENT = isElement(localPlayer)

local function hasPlayerInArg(arg)
    if isElement(arg) and getElementType(arg) == "player" then
        return arg
    end

    return false
end

function canPlayerInteract(player, data)
    data = data or {
        inVehicle = true,
        withChatbox = false,
        whileBlackout = false,
        requiresSpawned = true,
        whileOpenInventory = false,
        withWorldInteraction = false,
    }

    if not IS_CLIENT then
        if player and hasPlayerInArg(player) then
            localPlayer = player
        end
    end
    
    -- NOT `data.requiresSpawned == true and (...) or true` - that's the
    -- classic Lua a-and-b-or-c trap: when requiresSpawned is true AND the
    -- player genuinely isn't spawned, `b` is false, so the whole
    -- expression fell through `or true` and returned true anyway (the
    -- spawned check never actually blocked anything). This De Morgan'd
    -- form has no such trap - each operand of the outer `or` is
    -- independently correct on its own.
    local spawned = data.requiresSpawned ~= true or getElementData(localPlayer, ElementData.Player.SPAWNED) == true
    local hasBlackout = data.whileBlackout == false and (type(getElementData(localPlayer, ElementData.Player.BLACKOUT_UNTIL)) == "number") or false

    if data.inVehicle == true and isPedInVehicle(localPlayer) then
        return false
    end

    if IS_CLIENT then
        if data.withChatbox == false and isChatBoxInputActive() then
            return false
        end

        if data.withInteraction == false and exports.gm_interactions:isLookingForInteraction() then
            return false
        end

        if data.whileOpenInventory == false and exports.gm_items:hasOpenInventory() then
            return false
        end
    end

    return spawned and not hasBlackout
end

--- @param player element
-- @return boolean true if the player is both logged in and has spawned -
--- the minimum bar for any gameplay command to be meaningful. Distinct
--- from canPlayerInteract (which has no LOGGED concept and carries
--- client-only chatbox/interaction/inventory checks irrelevant to a
--- server-side command-permission gate).
function isPlayerReady(player)
    return getElementData(player, ElementData.Player.LOGGED) == true
        and getElementData(player, ElementData.Player.SPAWNED) == true
end