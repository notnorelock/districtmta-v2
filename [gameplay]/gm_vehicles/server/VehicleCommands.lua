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
        outputChatBox("Musisz być zalogowany i w grze, aby użyć tej komendy.", player, 255, 80, 80)
        return
    end

    if not canSpawnVehicles(player) then
        outputChatBox("Nie masz uprawnień do tej komendy.", player, 255, 80, 80)
        return
    end

    local model = tonumber(modelArg) or getVehicleModelFromName(tostring(modelArg or ""))
    if not model or model < 400 or model > 611 then
        outputChatBox("Użycie: /createvehicle <nazwa lub id modelu>", player, 255, 200, 0)
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        outputChatBox("Nie udało się ustalić Twojego konta.", player, 255, 80, 80)
        return
    end

    VehicleService.createPrivate(player, model, accountId, function(vehicle)
        if not vehicle then
            outputChatBox("Nie udało się stworzyć pojazdu.", player, 255, 80, 80)
            return
        end

        warpPedIntoVehicle(player, vehicle)
        outputChatBox("Stworzono pojazd prywatny: " .. (getVehicleNameFromModel(model) or tostring(model)), player, 0, 200, 0)

        Logger.security("VehicleCommands", "Player created a private vehicle", {
            player = getPlayerName(player),
            model = model,
            ownerAccountId = accountId,
        })
    end)
end)
