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

        -- Ownership alone (owner_account_id) is the access check for a
        -- PRIVATE vehicle, but the actual gates (canStartEngine,
        -- hasVehicleKey) only ever check for a physical VEHICLE_KEY item -
        -- without this, the very owner who just created the vehicle
        -- couldn't start its engine or lock/unlock it themselves. Fire-
        -- and-forget cross-resource call (see itemServiceGiveItem's own
        -- module comment) - gm_items sends its own success/error
        -- notification, this doesn't need to react to the result.
        local vehicleId = VehicleService.idOf(vehicle)
        if vehicleId then
            pcall(function()
                exports.gm_items:itemServiceGiveItem(player, "Kluczyki do pojazdu", 1, { vehicleId })
            end)
        end

        Logger.security("VehicleCommands", "Player created a private vehicle", {
            player = getPlayerName(player),
            model = model,
            ownerAccountId = accountId,
        })
    end)
end)

--- @param player element
-- @return boolean
local function canManageGroups(player)
    local role = PlayerService.getRole(player)
    if role == nil then
        return false
    end
    return Permissions.has(role, Permissions.Bit.MANAGE_GROUPS) == true
end

-- "/creategroupvehicle <nazwa grupy> <model>" - admin-only (MANAGE_GROUPS,
-- same tier as /creategroup itself), spawns a GROUP-purpose vehicle owned
-- by the named group at the admin's own position. Resolves the group by
-- name via gm_groups' own groupServiceFindGroupIdByName export (plain
-- data in/out, synchronous - GroupCache is fully in-memory there, see
-- that export's own comment) rather than gm_vehicles needing any direct
-- access to gm_groups' internal state.
addCommandHandler("creategroupvehicle", function(player, _, groupNameArg, modelArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if not canManageGroups(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    local groupName = tostring(groupNameArg or "")
    local model = tonumber(modelArg) or getVehicleModelFromName(tostring(modelArg or ""))
    if groupName == "" or not model or model < 400 or model > 611 then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /creategroupvehicle <nazwa grupy> <nazwa lub id modelu>" })
        return
    end

    local groupOk, groupId = pcall(function() return exports.gm_groups:groupServiceFindGroupIdByName(groupName) end)
    if not groupOk or not groupId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie znaleziono grupy o takiej nazwie." })
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się ustalić Twojego konta." })
        return
    end

    VehicleService.createGroupOwned(player, model, groupId, accountId, function(vehicle)
        if not vehicle then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się stworzyć pojazdu." })
            return
        end

        warpPedIntoVehicle(player, vehicle)
        NotificationService.send(player, {
            type = Enums.NotificationType.SUCCESS,
            message = "Stworzono pojazd grupowy dla '" .. groupName .. "': " .. (getVehicleNameFromModel(model) or tostring(model)),
        })

        Logger.security("VehicleCommands", "Admin created a group vehicle", {
            player = getPlayerName(player),
            model = model,
            groupId = groupId,
            groupName = groupName,
        })

        -- The vehicle just got a fresh vehicles.id it can't have had a
        -- moment ago - gm_groups' own GroupCache.vehicles/vehicleRankAllowlist
        -- needs to know it exists before groupServiceCanUseVehicle or the
        -- CEF Vehicles tab can see it. No allowlist yet (empty), matching
        -- a freshly-created rank having no members assigned to it either -
        -- the leader sets one via the panel.
        pcall(function() exports.gm_groups:groupServiceReloadVehicles(groupId) end)
    end)
end)
