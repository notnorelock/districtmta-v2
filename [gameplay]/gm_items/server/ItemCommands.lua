-- "/giveitem <nazwa> [ilość]" - gives the issuing admin's own account the
-- named ItemSchemes.lua item, for testing/support. Gated on
-- Permissions.Bit.GIVE_ITEM (MODERATOR+). Mirrors gm_vehicles/server/
-- VehicleCommands.lua's own structure.

--- @param player element
-- @return boolean
local function isReady(player)
    return getElementData(player, ElementData.Player.LOGGED) == true
        and getElementData(player, ElementData.Player.SPAWNED) == true
end

--- @param player element
-- @return boolean
local function canGiveItems(player)
    local role = PlayerService.getRole(player)
    if role == nil then
        return false
    end
    return Permissions.has(role, Permissions.Bit.GIVE_ITEM) == true
end

addCommandHandler("giveitem", function(player, _, ...)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if not canGiveItems(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    local args = { ... }
    local amount = tonumber(args[#args])
    local nameParts = args
    if amount then
        nameParts = {}
        for i = 1, #args - 1 do
            nameParts[i] = args[i]
        end
    else
        amount = 1
    end

    local schemeKey = table.concat(nameParts, " ")
    if schemeKey == "" or not ItemSchemes.get(schemeKey) then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /giveitem <nazwa przedmiotu> [ilość] - nieznana nazwa." })
        return
    end

    ItemService.give(player, schemeKey, amount, nil, function(ok)
        if not ok then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się dodać przedmiotu (za duży ciężar lub błąd)." })
            return
        end

        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = ("Dodano przedmiot: %s x%d"):format(schemeKey, amount) })
        Logger.security("ItemCommands", "Player gave themselves an item", {
            player = getPlayerName(player),
            schemeKey = schemeKey,
            amount = amount,
        })
    end)
end)
