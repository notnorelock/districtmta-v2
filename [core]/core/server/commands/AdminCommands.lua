-- /duty, /report, /apanel, /reports - see docs/Architecture.md's
-- "Admin duty, panel, and reports" section.
CommandRegistry.register("duty", Permissions.Bit.TOGGLE_DUTY, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/duty can only be used in-game")
        return
    end

    local nowOnDuty = not PlayerService.isOnDuty(player)
    PlayerService.setDuty(player, nowOnDuty)

    local accountId = PlayerService.getAccountId(player)
    if nowOnDuty then
        AdminDutyStatsService.startSession(accountId)
    else
        AdminDutyStatsService.finishSession(accountId)
    end

    Logger.security("AdminCommands", "Duty toggled", {
        player = getPlayerName(player),
        accountId = accountId,
        onDuty = nowOnDuty,
    })
    CommandRegistry.reply(player, nowOnDuty and "Jesteś teraz na służbie." or "Zszedłeś ze służby.")

    -- core_admin's KeyBinds.lua binds/unbinds F6/F7 off this - see
    -- Events.ADMIN_DUTY_CHANGED's own comment.
    triggerClientEvent(player, Events.ADMIN_DUTY_CHANGED, player, nowOnDuty)
end)

CommandRegistry.register("report", nil, function(player, target, ...)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/report can only be used in-game")
        return
    end

    local reporterAccountId = PlayerService.getAccountId(player)
    if not reporterAccountId then
        CommandRegistry.reply(player, "Musisz być zalogowany, aby zgłosić gracza.")
        return
    end

    if not target then
        CommandRegistry.reply(player, "Usage: /report <login|id|nick> <powód>")
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        CommandRegistry.reply(player, "Usage: /report <login|id|nick> <powód>")
        return
    end

    CommandRegistry.resolveTargetAccount(player, target, function(reportedAccount)
        ReportService.create(reporterAccountId, reportedAccount.id, reason, function(report)
            CommandRegistry.reply(player, "Zgłoszenie na '" .. reportedAccount.login .. "' zostało wysłane.")
        end, function(code, message)
            CommandRegistry.reply(player, "Nie udało się wysłać zgłoszenia: " .. tostring(message or code))
        end)
    end)
end)

CommandRegistry.register("reports", Permissions.Bit.VIEW_REPORTS, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/reports can only be used in-game")
        return
    end

    triggerClientEvent(player, Events.REPORTS_OVERLAY_TOGGLE, player)
end)

CommandRegistry.register("apanel", Permissions.Bit.ADMIN_PANEL, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/apanel can only be used in-game")
        return
    end

    triggerClientEvent(player, Events.ADMIN_PANEL_TOGGLE, player)
end)

--- Moves `to` to `from`'s position, dimension, and interior.
-- @param from element
-- @param to element
local function copyPosition(from, to)
    local x, y, z = getElementPosition(from)
    setElementDimension(to, getElementDimension(from))
    setElementInterior(to, getElementInterior(from))
    setElementPosition(to, x, y, z)
end

--- Finds a live world vehicle by its gm_vehicles database row id. `core`
--- has no reverse id->element map of its own (gm_vehicles' own
--- VehicleService.lua only tracks the forward element->id direction
--- privately) - this scans and matches on ElementData.Vehicle.ID
--- directly instead, exactly like gm_items/server/ItemUseHandlers.lua's
--- own vehicle-key lookup does from a different resource. A plain
--- ElementData read, not a call into gm_vehicles, so there's no resource-
--- boundary/start-order concern (see docs/Architecture.md's "the one
--- hard rule" - only callbacks/function values are restricted, not data
--- reads off an element any resource can already see).
-- @param id number
-- @return vehicle|nil
local function findVehicleById(id)
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if getElementData(vehicle, ElementData.Vehicle.ID) == id then
            return vehicle
        end
    end
    return nil
end

CommandRegistry.register("goto", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/goto can only be used in-game")
        return
    end

    if not target then
        CommandRegistry.reply(player, "Usage: /goto <login|id|nick>")
        return
    end

    local targetPlayer, ambiguous = PlayerId.tryResolve(target)
    if not targetPlayer then
        CommandRegistry.reply(player, ambiguous
            and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
            or "Nie znaleziono gracza online o podanym loginie/nicku/id.")
        return
    end

    if targetPlayer == player then
        CommandRegistry.reply(player, "Nie możesz teleportować się do samego siebie.")
        return
    end

    copyPosition(targetPlayer, player)

    Logger.security("AdminCommands", "Teleported to player", {
        player = getPlayerName(player),
        target = getPlayerName(targetPlayer),
    })
    CommandRegistry.reply(player, "Teleportowano do " .. getPlayerName(targetPlayer) .. ".")
end)

CommandRegistry.register("gethere", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/gethere can only be used in-game")
        return
    end

    if not target then
        CommandRegistry.reply(player, "Usage: /gethere <login|id|nick>")
        return
    end

    local targetPlayer, ambiguous = PlayerId.tryResolve(target)
    if not targetPlayer then
        CommandRegistry.reply(player, ambiguous
            and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
            or "Nie znaleziono gracza online o podanym loginie/nicku/id.")
        return
    end

    if targetPlayer == player then
        CommandRegistry.reply(player, "Nie możesz przywołać samego siebie.")
        return
    end

    copyPosition(player, targetPlayer)

    Logger.security("AdminCommands", "Teleported player to self", {
        player = getPlayerName(player),
        target = getPlayerName(targetPlayer),
    })
    CommandRegistry.reply(player, "Przywołano " .. getPlayerName(targetPlayer) .. " do siebie.")
    CommandRegistry.reply(targetPlayer, "Zostałeś przywołany przez " .. getPlayerName(player) .. ".")
end)

--- Teleports `player` INTO the vehicle's driver seat if it's free,
--- otherwise just to its position (same "best effort" as walking up to a
--- vehicle yourself) - either way the admin ends up at the vehicle,
--- warpPedIntoVehicle only additionally saves them the walk/enter animation.
-- @param player element
-- @param vehicle vehicle
local function teleportToVehicle(player, vehicle)
    copyPosition(vehicle, player)
    if getVehicleOccupant(vehicle, 0) then
        return false
    end
    return warpPedIntoVehicle(player, vehicle, 0)
end

CommandRegistry.register("gotocar", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/gotocar can only be used in-game")
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Usage: /gotocar <id pojazdu>")
        return
    end

    local vehicle = findVehicleById(id)
    if not vehicle then
        CommandRegistry.reply(player, "Nie znaleziono pojazdu o podanym id.")
        return
    end

    local warpedIn = teleportToVehicle(player, vehicle)

    Logger.security("AdminCommands", "Teleported to vehicle", {
        player = getPlayerName(player),
        vehicleId = id,
        warpedIn = warpedIn,
    })
    CommandRegistry.reply(player, warpedIn
        and "Teleportowano do pojazdu (id " .. id .. ")."
        or "Teleportowano obok pojazdu (id " .. id .. ") - miejsce kierowcy zajęte.")
end)

CommandRegistry.register("getcar", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/getcar can only be used in-game")
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Usage: /getcar <id pojazdu>")
        return
    end

    local vehicle = findVehicleById(id)
    if not vehicle then
        CommandRegistry.reply(player, "Nie znaleziono pojazdu o podanym id.")
        return
    end

    copyPosition(player, vehicle)

    Logger.security("AdminCommands", "Teleported vehicle to self", {
        player = getPlayerName(player),
        vehicleId = id,
    })
    CommandRegistry.reply(player, "Przywołano pojazd (id " .. id .. ") do siebie.")
end)

local DEFAULT_HEALTH = 100

CommandRegistry.register("heal", Permissions.Bit.HEAL, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/heal can only be used in-game")
        return
    end

    local targetPlayer = player

    if target then
        local resolved, ambiguous = PlayerId.tryResolve(target)
        if not resolved then
            CommandRegistry.reply(player, ambiguous
                and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
                or "Nie znaleziono gracza online o podanym loginie/nicku/id.")
            return
        end
        targetPlayer = resolved
    end

    -- A dead ped can't have its health set directly (MTA silently no-ops)
    -- - respawn it in place first, at its current model/dimension/
    -- interior, same as it was at the moment of death.
    if isPedDead(targetPlayer) then
        local x, y, z = getElementPosition(targetPlayer)
        local _, _, heading = getElementRotation(targetPlayer)
        local model = getElementModel(targetPlayer)
        local dimension = getElementDimension(targetPlayer)
        local interior = getElementInterior(targetPlayer)

        spawnPlayer(targetPlayer, x, y, z, heading, model, interior, dimension)
        setElementInterior(targetPlayer, interior)
        setElementDimension(targetPlayer, dimension)
    end

    setElementHealth(targetPlayer, DEFAULT_HEALTH)

    Logger.security("AdminCommands", "Player healed", {
        player = getPlayerName(player),
        target = getPlayerName(targetPlayer),
    })

    if targetPlayer == player then
        CommandRegistry.reply(player, "Zostałeś uleczony.")
    else
        CommandRegistry.reply(player, "Uleczono " .. getPlayerName(targetPlayer) .. ".")
        CommandRegistry.reply(targetPlayer, "Zostałeś uleczony przez " .. getPlayerName(player) .. ".")
    end
end)

-- Self-toggle only (no target) - bound to J by core_admin's KeyBinds.lua
-- while on duty, same as F6/F7.
CommandRegistry.register("jetpack", Permissions.Bit.JETPACK, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/jetpack can only be used in-game")
        return
    end

    local hasJetpack = not isPedWearingJetpack(player)
    if hasJetpack then
        givePedJetPack(player)
    else
        removePedJetPack(player)
    end

    Logger.security("AdminCommands", "Jetpack toggled", {
        player = getPlayerName(player),
        hasJetpack = hasJetpack,
    })
    CommandRegistry.reply(player, hasJetpack and "Jetpack włączony." or "Jetpack wyłączony.")
end)
