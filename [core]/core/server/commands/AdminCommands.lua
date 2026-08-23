-- /duty, /report, /apanel, /reports - see docs/Architecture.md's
-- "Admin duty, panel, and reports" section.
CommandRegistry.register("duty", Permissions.Bit.TOGGLE_DUTY, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/duty można użyć tylko w grze", Enums.NotificationType.WARNING)
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
    CommandRegistry.reply(player, nowOnDuty and "Jesteś teraz na służbie." or "Zszedłeś ze służby.", Enums.NotificationType.SUCCESS)

    -- core_admin's KeyBinds.lua binds/unbinds F6/F7 off this - see
    -- Events.ADMIN_DUTY_CHANGED's own comment.
    triggerClientEvent(player, Events.ADMIN_DUTY_CHANGED, player, nowOnDuty)
end)

CommandRegistry.register("report", nil, function(player, target, ...)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/report można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local reporterAccountId = PlayerService.getAccountId(player)
    if not reporterAccountId then
        CommandRegistry.reply(player, "Musisz być zalogowany, aby zgłosić gracza.", Enums.NotificationType.ERROR)
        return
    end

    if not target then
        CommandRegistry.reply(player, "Użycie: /report <login|id|nick> <powód>", Enums.NotificationType.WARNING)
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        CommandRegistry.reply(player, "Użycie: /report <login|id|nick> <powód>", Enums.NotificationType.WARNING)
        return
    end

    CommandRegistry.resolveTargetAccount(player, target, function(reportedAccount)
        ReportService.create(reporterAccountId, reportedAccount.id, reason, function(report)
            CommandRegistry.reply(player, "Zgłoszenie na '" .. reportedAccount.login .. "' zostało wysłane.", Enums.NotificationType.SUCCESS)
        end, function(code, message)
            CommandRegistry.reply(player, "Nie udało się wysłać zgłoszenia: " .. tostring(message or code), Enums.NotificationType.ERROR)
        end)
    end)
end)

CommandRegistry.register("reports", Permissions.Bit.VIEW_REPORTS, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/reports można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    triggerClientEvent(player, Events.REPORTS_OVERLAY_TOGGLE, player)
end)

CommandRegistry.register("apanel", Permissions.Bit.ADMIN_PANEL, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/apanel można użyć tylko w grze", Enums.NotificationType.WARNING)
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
        CommandRegistry.reply(player, "/goto można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    if not target then
        CommandRegistry.reply(player, "Użycie: /goto <login|id|nick>", Enums.NotificationType.WARNING)
        return
    end

    local targetPlayer, ambiguous = PlayerId.tryResolve(target)
    if not targetPlayer then
        CommandRegistry.reply(player, ambiguous
            and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
            or "Nie znaleziono gracza online o podanym loginie/nicku/id.", Enums.NotificationType.ERROR)
        return
    end

    if targetPlayer == player then
        CommandRegistry.reply(player, "Nie możesz teleportować się do samego siebie.", Enums.NotificationType.ERROR)
        return
    end

    copyPosition(targetPlayer, player)

    Logger.security("AdminCommands", "Teleported to player", {
        player = getPlayerName(player),
        target = getPlayerName(targetPlayer),
    })
    CommandRegistry.reply(player, "Teleportowano do " .. getPlayerName(targetPlayer) .. ".", Enums.NotificationType.SUCCESS)
end)

CommandRegistry.register("gethere", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/gethere można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    if not target then
        CommandRegistry.reply(player, "Użycie: /gethere <login|id|nick>", Enums.NotificationType.WARNING)
        return
    end

    local targetPlayer, ambiguous = PlayerId.tryResolve(target)
    if not targetPlayer then
        CommandRegistry.reply(player, ambiguous
            and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
            or "Nie znaleziono gracza online o podanym loginie/nicku/id.", Enums.NotificationType.ERROR)
        return
    end

    if targetPlayer == player then
        CommandRegistry.reply(player, "Nie możesz przywołać samego siebie.", Enums.NotificationType.ERROR)
        return
    end

    copyPosition(player, targetPlayer)

    Logger.security("AdminCommands", "Teleported player to self", {
        player = getPlayerName(player),
        target = getPlayerName(targetPlayer),
    })
    CommandRegistry.reply(player, "Przywołano " .. getPlayerName(targetPlayer) .. " do siebie.", Enums.NotificationType.SUCCESS)
    CommandRegistry.reply(targetPlayer, "Zostałeś przywołany przez " .. getPlayerName(player) .. ".", Enums.NotificationType.INFO)
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
        CommandRegistry.reply(player, "/gotocar można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /gotocar <id pojazdu>", Enums.NotificationType.WARNING)
        return
    end

    local vehicle = findVehicleById(id)
    if not vehicle then
        CommandRegistry.reply(player, "Nie znaleziono pojazdu o podanym id.", Enums.NotificationType.ERROR)
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
        or "Teleportowano obok pojazdu (id " .. id .. ") - miejsce kierowcy zajęte.", Enums.NotificationType.SUCCESS)
end)

CommandRegistry.register("getcar", Permissions.Bit.TELEPORT, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/getcar można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /getcar <id pojazdu>", Enums.NotificationType.WARNING)
        return
    end

    local vehicle = findVehicleById(id)
    if not vehicle then
        CommandRegistry.reply(player, "Nie znaleziono pojazdu o podanym id.", Enums.NotificationType.ERROR)
        return
    end

    copyPosition(player, vehicle)

    Logger.security("AdminCommands", "Teleported vehicle to self", {
        player = getPlayerName(player),
        vehicleId = id,
    })
    CommandRegistry.reply(player, "Przywołano pojazd (id " .. id .. ") do siebie.", Enums.NotificationType.SUCCESS)
end)

local DEFAULT_HEALTH = 100

CommandRegistry.register("heal", Permissions.Bit.HEAL, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/heal można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local targetPlayer = player

    if target then
        local resolved, ambiguous = PlayerId.tryResolve(target)
        if not resolved then
            CommandRegistry.reply(player, ambiguous
                and "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza."
                or "Nie znaleziono gracza online o podanym loginie/nicku/id.", Enums.NotificationType.ERROR)
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
        CommandRegistry.reply(player, "Zostałeś uleczony.", Enums.NotificationType.SUCCESS)
    else
        CommandRegistry.reply(player, "Uleczono " .. getPlayerName(targetPlayer) .. ".", Enums.NotificationType.SUCCESS)
        CommandRegistry.reply(targetPlayer, "Zostałeś uleczony przez " .. getPlayerName(player) .. ".", Enums.NotificationType.INFO)
    end
end)

-- Self-toggle only (no target) - bound to J by core_admin's KeyBinds.lua
-- while on duty, same as F6/F7.
CommandRegistry.register("jetpack", Permissions.Bit.JETPACK, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/jetpack można użyć tylko w grze", Enums.NotificationType.WARNING)
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
    CommandRegistry.reply(player, hasJetpack and "Jetpack włączony." or "Jetpack wyłączony.", Enums.NotificationType.SUCCESS)
end)

-- /createstore, /addstorespawn, /clearstorespawns, /movestore,
-- /setstorepos, /stores, /removestore - vehicle_stores table management
-- (VehicleStoreRepository.lua). Lives
-- here rather than in gm_vehicles because the table/repository itself
-- lives in core (see Vehicle.lua's own module comment on why every
-- model/repository lives in core, never in the gameplay resource that
-- consumes it) - these commands talk to VehicleStoreRepository directly,
-- no VehicleBridge round trip needed since this is the same resource.
-- Every command that actually changes a row fires
-- Events.VEHICLE_STORE_RELOAD once its write finishes, so gm_vehicles'
-- own VehicleStorageService.reload() picks it up live - no manual
-- gm_vehicles restart needed (see that event's own comment in Events.lua).
local function reloadVehicleStores()
    triggerEvent(Events.VEHICLE_STORE_RELOAD, resourceRoot)
end
CommandRegistry.register("createstore", Permissions.Bit.VEHICLE_ADMIN, function(player, name)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/createstore można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    if type(name) ~= "string" or name == "" then
        CommandRegistry.reply(player, "Użycie: /createstore <nazwa>", Enums.NotificationType.WARNING)
        return
    end

    local x, y, z = getElementPosition(player)
    local _, _, heading = getElementRotation(player)

    VehicleStoreRepository.create({
        name = name,
        enter_position = { x, y, z },
        -- Seeded with the admin's own current spot as the first retrieval
        -- point - see /addstorespawn to add more afterward. A store with
        -- zero spawn positions is skipped entirely by
        -- VehicleStorageService.lua's own loader (logged as a warning),
        -- so this avoids creating a lot nothing can ever be retrieved from.
        spawn_positions = { { x, y, z, heading, 0, 0 } },
    }, function(ok, storeOrError)
        if not ok then
            CommandRegistry.reply(player, "Nie udało się stworzyć przechowalni: " .. tostring(storeOrError), Enums.NotificationType.ERROR)
            return
        end

        Logger.security("AdminCommands", "Vehicle store created", {
            player = getPlayerName(player),
            storeId = storeOrError.id,
            name = name,
        })
        reloadVehicleStores()
        CommandRegistry.reply(player, "Stworzono przechowalnię '" .. name .. "' (id " .. storeOrError.id .. ").", Enums.NotificationType.SUCCESS)
    end)
end)

-- Same as /createstore but GROUP-purpose: dedicated to one group's own
-- vehicles (VehicleStorageService.lua's own purpose-aware sendStoreItems/
-- tryStoreVehicle branching), not a shared PRIVATE pool. Resolves the
-- group by name via gm_groups' groupServiceFindGroupIdByName export
-- (plain data in/out, synchronous) - core has no other access to
-- gm_groups' internal state, same cross-resource pattern
-- gm_vehicles/server/VehicleCommands.lua's own /creategroupvehicle uses.
CommandRegistry.register("creategroupstore", Permissions.Bit.MANAGE_GROUPS, function(player, groupName, name)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/creategroupstore można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    if type(groupName) ~= "string" or groupName == "" or type(name) ~= "string" or name == "" then
        CommandRegistry.reply(player, "Użycie: /creategroupstore <nazwa grupy> <nazwa przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    local groupOk, groupId = pcall(function() return exports.gm_groups:groupServiceFindGroupIdByName(groupName) end)
    if not groupOk or not groupId then
        CommandRegistry.reply(player, "Nie znaleziono grupy o takiej nazwie.", Enums.NotificationType.ERROR)
        return
    end

    local x, y, z = getElementPosition(player)
    local _, _, heading = getElementRotation(player)

    VehicleStoreRepository.create({
        name = name,
        purpose = Enums.VehicleStorePurpose.GROUP,
        group_id = groupId,
        enter_position = { x, y, z },
        spawn_positions = { { x, y, z, heading, 0, 0 } },
    }, function(ok, storeOrError)
        if not ok then
            CommandRegistry.reply(player, "Nie udało się stworzyć przechowalni: " .. tostring(storeOrError), Enums.NotificationType.ERROR)
            return
        end

        Logger.security("AdminCommands", "Group vehicle store created", {
            player = getPlayerName(player),
            storeId = storeOrError.id,
            name = name,
            groupId = groupId,
            groupName = groupName,
        })
        reloadVehicleStores()
        CommandRegistry.reply(player, "Stworzono przechowalnię grupową '" .. name .. "' dla '" .. groupName .. "' (id " .. storeOrError.id .. ").", Enums.NotificationType.SUCCESS)
    end)
end)

CommandRegistry.register("addstorespawn", Permissions.Bit.VEHICLE_ADMIN, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/addstorespawn można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /addstorespawn <id przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    VehicleStoreRepository.findById(id, function(ok, storeOrError)
        if not ok or not storeOrError then
            CommandRegistry.reply(player, "Nie znaleziono przechowalni o podanym id.", Enums.NotificationType.ERROR)
            return
        end

        local x, y, z = getElementPosition(player)
        local _, _, heading = getElementRotation(player)

        local spawnPositions = storeOrError.spawn_positions or {}
        spawnPositions[#spawnPositions + 1] = { x, y, z, heading, 0, 0 }

        VehicleStoreRepository.update(id, { spawn_positions = spawnPositions }, function(updateOk, affectedOrError)
            if not updateOk then
                CommandRegistry.reply(player, "Nie udało się dodać punktu odbioru: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AdminCommands", "Vehicle store spawn point added", {
                player = getPlayerName(player),
                storeId = id,
                total = #spawnPositions,
            })
            reloadVehicleStores()
            CommandRegistry.reply(player, "Dodano punkt odbioru do przechowalni '" .. storeOrError.name .. "' (" .. #spawnPositions .. " łącznie).", Enums.NotificationType.SUCCESS)
        end)
    end)
end)

-- Clears the ENTIRE spawn_positions list back to empty, to redo it from
-- scratch with /addstorespawn - deliberately no "remove just one" variant
-- (spawn positions have no id/index a player could reasonably reference
-- from in-game, unlike vehicle_stores rows themselves). A lot with zero
-- spawn_positions is skipped entirely by VehicleStorageService.lua's own
-- reload() (its marker/zone disappear until at least one is added back) -
-- the reply below says so explicitly rather than leaving that a surprise.
CommandRegistry.register("clearstorespawns", Permissions.Bit.VEHICLE_ADMIN, function(player, target)
    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /clearstorespawns <id przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    VehicleStoreRepository.findById(id, function(ok, storeOrError)
        if not ok or not storeOrError then
            CommandRegistry.reply(player, "Nie znaleziono przechowalni o podanym id.", Enums.NotificationType.ERROR)
            return
        end

        VehicleStoreRepository.update(id, { spawn_positions = {} }, function(updateOk, affectedOrError)
            if not updateOk then
                CommandRegistry.reply(player, "Nie udało się usunąć punktów odbioru: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AdminCommands", "Vehicle store spawn points cleared", {
                player = CommandRegistry.issuerLabel(player),
                storeId = id,
            })
            reloadVehicleStores()
            CommandRegistry.reply(player, "Usunięto wszystkie punkty odbioru przechowalni '" .. storeOrError.name .. "'. Przechowalnia jest teraz nieaktywna, dopóki nie dodasz nowego przez /addstorespawn.", Enums.NotificationType.WARNING)
        end)
    end)
end)

CommandRegistry.register("movestore", Permissions.Bit.VEHICLE_ADMIN, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/movestore można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /movestore <id przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    VehicleStoreRepository.findById(id, function(ok, storeOrError)
        if not ok or not storeOrError then
            CommandRegistry.reply(player, "Nie znaleziono przechowalni o podanym id.", Enums.NotificationType.ERROR)
            return
        end

        -- Only moves the ENTER marker (where the panel opens) - the
        -- spawn_positions list (where a retrieved vehicle is placed) is
        -- untouched, same reasoning /addstorespawn keeps them separate:
        -- an admin moving the marker itself hasn't necessarily moved
        -- where cars should come out too.
        local x, y, z = getElementPosition(player)

        VehicleStoreRepository.update(id, { enter_position = { x, y, z } }, function(updateOk, affectedOrError)
            if not updateOk then
                CommandRegistry.reply(player, "Nie udało się przenieść przechowalni: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AdminCommands", "Vehicle store moved", {
                player = getPlayerName(player),
                storeId = id,
            })
            reloadVehicleStores()
            CommandRegistry.reply(player, "Przeniesiono wejście przechowalni '" .. storeOrError.name .. "' w twoje miejsce.", Enums.NotificationType.SUCCESS)
        end)
    end)
end)

-- Sets/moves the SEPARATE store marker (drive a vehicle onto it, press G -
-- see VehicleStorageService.lua's own module comment on why this is a
-- different spot from enter_position's retrieval panel marker).
CommandRegistry.register("setstorepos", Permissions.Bit.VEHICLE_ADMIN, function(player, target)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/setstorepos można użyć tylko w grze", Enums.NotificationType.WARNING)
        return
    end

    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /setstorepos <id przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    VehicleStoreRepository.findById(id, function(ok, storeOrError)
        if not ok or not storeOrError then
            CommandRegistry.reply(player, "Nie znaleziono przechowalni o podanym id.", Enums.NotificationType.ERROR)
            return
        end

        local x, y, z = getElementPosition(player)

        VehicleStoreRepository.update(id, { store_position = { x, y, z } }, function(updateOk, affectedOrError)
            if not updateOk then
                CommandRegistry.reply(player, "Nie udało się ustawić miejsca oddawania: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AdminCommands", "Vehicle store store_position set", {
                player = getPlayerName(player),
                storeId = id,
            })
            reloadVehicleStores()
            CommandRegistry.reply(player, "Ustawiono miejsce oddawania pojazdów dla przechowalni '" .. storeOrError.name .. "'.", Enums.NotificationType.SUCCESS)
        end)
    end)
end)

CommandRegistry.register("stores", Permissions.Bit.VEHICLE_ADMIN, function(player)
    VehicleStoreRepository.findAll(function(ok, storesOrError)
        if not ok then
            CommandRegistry.reply(player, "Nie udało się wczytać przechowalni: " .. tostring(storesOrError), Enums.NotificationType.ERROR)
            return
        end

        if #storesOrError == 0 then
            CommandRegistry.reply(player, "Nie ma jeszcze żadnej przechowalni.", Enums.NotificationType.INFO)
            return
        end

        local lines = {}
        for _, store in ipairs(storesOrError) do
            local spawnCount = type(store.spawn_positions) == "table" and #store.spawn_positions or 0
            lines[#lines + 1] = ("[%d] %s (%d pkt. odbioru)"):format(store.id, store.name, spawnCount)
        end
        CommandRegistry.reply(player, table.concat(lines, "\n"), Enums.NotificationType.INFO)
    end)
end)

CommandRegistry.register("removestore", Permissions.Bit.VEHICLE_ADMIN, function(player, target)
    local id = tonumber(target)
    if not id then
        CommandRegistry.reply(player, "Użycie: /removestore <id przechowalni>", Enums.NotificationType.WARNING)
        return
    end

    -- Refuses to delete a lot with vehicles still parked in it - those
    -- rows would keep their now-dangling store_id, permanently hiding
    -- them from the world (VehicleRepository.findAllPrivate only spawns
    -- store_id IS NULL rows) with no way left to retrieve them.
    VehicleRepository.findByStoreId(id, function(ok, vehiclesOrError)
        if not ok then
            CommandRegistry.reply(player, "Nie udało się sprawdzić przechowalni: " .. tostring(vehiclesOrError), Enums.NotificationType.ERROR)
            return
        end

        if #vehiclesOrError > 0 then
            CommandRegistry.reply(player, "Ta przechowalnia zawiera " .. #vehiclesOrError .. " pojazd(y/ów) - nie można jej usunąć.", Enums.NotificationType.ERROR)
            return
        end

        VehicleStoreRepository.delete(id, function(deleteOk, affectedOrError)
            if not deleteOk or affectedOrError == 0 then
                CommandRegistry.reply(player, "Nie znaleziono przechowalni o podanym id.", Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AdminCommands", "Vehicle store removed", {
                player = CommandRegistry.issuerLabel(player),
                storeId = id,
            })
            reloadVehicleStores()
            CommandRegistry.reply(player, "Usunięto przechowalnię (id " .. id .. ").", Enums.NotificationType.SUCCESS)
        end)
    end)
end)
