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
    
    local spawned = data.requiresSpawned == true and (getElementData(localPlayer, ElementData.Player.SPAWNED) == true) or true
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

-- TODO @ canLocalPlayerUse
--[[
    - może używać tego interfejsu?
    - inne jakies gowna kekw
]]

-- function canLocalPlayerUse()
--     if not isElement(localPlayer) then
--         if hasPlayerInArg(player) then
--             localPlayer = player
--         else
--             return false
--         end
--     end
--     local spawned = getElementData(localPlayer, ElementData.Player.SPAWNED) == true
--     local hasBlackout = type(getElementData(localPlayer, ElementData.Player.BLACKOUT_UNTIL)) == "number"
--     return spawned and not hasBlackout
-- end