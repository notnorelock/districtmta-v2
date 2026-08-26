-- "/veh <name|id>", "/fix", "/flip" - available to every logged-in,
-- spawned player, no permission bit required (unlike core's admin
-- commands - see CommandRegistry.lua for that gated pattern, unused here
-- on purpose).

local SPAWN_OFFSET_DISTANCE = 3
local FLIP_LIFT_HEIGHT = 0.5

local function isReady(player)
    return exports.core_shared:isPlayerReady(player)
end

--- Driver-only lookup, since /fix and /flip acting on a vehicle a mere
--- passenger doesn't control would be surprising/abusable.
-- @param player element
-- @return vehicle|nil
local function driverVehicleOf(player)
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle and getPedOccupiedVehicleSeat(player) == 0 then
        return vehicle
    end
    return nil
end

--- @param player element
-- @return number, number, number, number spawn x, y, z, heading - a few
--         meters in front of the player, at their current z
local function spawnPositionInFrontOf(player)
    local x, y, z = getElementPosition(player)
    local heading = getPedRotation(player)
    local rad = math.rad(heading)

    return x + math.sin(-rad) * SPAWN_OFFSET_DISTANCE, y + math.cos(-rad) * SPAWN_OFFSET_DISTANCE, z, heading
end

addCommandHandler("veh", function(player, _, modelArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if type(modelArg) ~= "string" or modelArg == "" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /veh <nazwa lub id pojazdu>" })
        return
    end

    local model = tonumber(modelArg) or getVehicleModelFromName(modelArg)

    -- Valid MTA vehicle model id range - also catches "/veh 99999" (a
    -- number, but not a real vehicle) since createVehicle itself doesn't
    -- reject an out-of-range model, it just fails silently later.
    if not model or model < 400 or model > 611 then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nieznany pojazd: '" .. modelArg .. "'. Podaj nazwę (np. infernus) lub poprawne id modelu." })
        return
    end

    local x, y, z, heading = spawnPositionInFrontOf(player)
    local vehicle = createVehicle(model, x, y, z, 0, 0, heading)

    if not vehicle then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się stworzyć pojazdu." })
        return
    end

    setElementDimension(vehicle, getElementDimension(player))
    setElementInterior(vehicle, getElementInterior(player))
    warpPedIntoVehicle(player, vehicle)

    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Zaspawnowano pojazd: " .. (getVehicleNameFromModel(model) or tostring(model)) })

    Logger.info("VehicleCommands", "Player spawned a vehicle", {
        player = getPlayerName(player),
        model = model,
    })
end)

addCommandHandler("fix", function(player)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    local vehicle = driverVehicleOf(player)
    if not vehicle then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz siedzieć za kierownicą pojazdu." })
        return
    end

    fixVehicle(vehicle)
    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Pojazd naprawiony." })

    Logger.info("VehicleCommands", "Player fixed a vehicle", { player = getPlayerName(player) })
end)

addCommandHandler("flip", function(player)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    local vehicle = driverVehicleOf(player)
    if not vehicle then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz siedzieć za kierownicą pojazdu." })
        return
    end

    local x, y, z = getElementPosition(vehicle)
    local _, _, heading = getElementRotation(vehicle)

    setElementPosition(vehicle, x, y, z + FLIP_LIFT_HEIGHT)
    setElementRotation(vehicle, 0, 0, heading)
    setElementVelocity(vehicle, 0, 0, 0)
    setElementAngularVelocity(vehicle, 0, 0, 0)

    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Pojazd wyprostowany." })

    Logger.info("VehicleCommands", "Player flipped a vehicle", { player = getPlayerName(player) })
end)
