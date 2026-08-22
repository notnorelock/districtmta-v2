-- "/createvehicle <model>" - spawns a new PRIVATE vehicle owned by the
-- issuing admin's own account, at their current position. Gated on
-- Permissions.Bit.SPAWN_VEHICLE (MODERATOR+) via GlobalResources.lua's
-- Permissions proxy - CommandRegistry itself isn't reachable here (it
-- lives in core, and addCommandHandler is a per-resource registration,
-- not something to proxy across resources).

--- @param player element
-- @return boolean
local function isReady(player)
    return getElementData(player, ElementData.Player.LOGGED) == true
        and getElementData(player, ElementData.Player.SPAWNED) == true
end

--- @param player element
-- @return boolean
local function canSpawnVehicles(player)
    local role = PlayerService.getRole(player)
    if role == nil then
        return false
    end
    return Permissions.has(role, Permissions.Bit.SPAWN_VEHICLE) == true
end

addCommandHandler("createvehicle", function(player, _, modelArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if not canSpawnVehicles(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    local model = tonumber(modelArg) or getVehicleModelFromName(tostring(modelArg or ""))
    if not model or model < 400 or model > 611 then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /createvehicle <nazwa lub id modelu>" })
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się ustalić Twojego konta." })
        return
    end

    VehicleService.createPrivate(player, model, accountId, function(vehicle)
        if not vehicle then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się stworzyć pojazdu." })
            return
        end

        warpPedIntoVehicle(player, vehicle)
        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Stworzono pojazd prywatny: " .. (getVehicleNameFromModel(model) or tostring(model)) })

        Logger.security("VehicleCommands", "Player created a private vehicle", {
            player = getPlayerName(player),
            model = model,
            ownerAccountId = accountId,
        })
    end)
end)
