-- Vehicle storage lots: walk into a lot's enter marker to see/retrieve
-- every private vehicle stored there (store_id = that lot's id) that's
-- either YOUR OWN, or someone else's you're carrying a VEHICLE_KEY item
-- for (see playerHasKeyTo below - the same "you physically have the key"
-- gate gm_vehicles_interaction already uses to let a borrowed vehicle's
-- engine start) - a SEPARATE store zone is where you drive a
-- vehicle IN to store it, no keypress at all: entering the zone stores it
-- immediately if it's your own PRIVATE vehicle (see onStoreZoneHit/
-- tryStoreVehicle below). The two used to be the same spot, kept apart
-- now so retrieving never requires fighting the panel's own right-click
-- cursor toggle, and so a lot's retrieval panel location and its physical
-- drive-in drop-off spot can differ (e.g. a garage with one door in, one
-- door out). Lot locations themselves (enter_position/store_position/
-- spawn_positions) are admin-configured rows in the vehicle_stores table
-- (VehicleStoreRepository.lua), loaded once at resource start and again
-- live on Events.VEHICLE_STORE_RELOAD - see this file's own reload().
VehicleStorageService = VehicleStorageService or {}

local RETRIEVE_COOLDOWN_MS = 5000
-- Radius (world units) checked around a spawn_positions entry for an
-- already-parked vehicle before using it - matches the ~4-5m a real
-- vehicle model roughly occupies, generous enough to avoid two vehicles
-- visually overlapping without being so large that a lot with tightly-
-- packed spawn points always reads as "occupied".
local SPAWN_POSITION_CLEAR_RADIUS = 4
-- How often the store-zone occupancy check below re-scans for a vehicle
-- that's been blocking a drop-off zone.
local STORE_ZONE_CHECK_INTERVAL_MS = 15000
-- How long a vehicle can sit in a store zone (not a private vehicle
-- successfully stored, that removes it from the world immediately - this
-- is for anything left behind blocking the marker: a passenger vehicle,
-- someone else's car, a vehicle whose store attempt was rejected) before
-- it's destroyed to keep the drop-off zone usable.
local STORE_ZONE_GRACE_MS = 60000

-- Tells core/server/database/repositories/VehicleRepository.lua "write
-- SQL NULL for this column" - must match that file's own NULL_SENTINEL
-- constant exactly (gm_vehicles has no access to Model.NULL, and
-- triggerEvent copies tables across the resource boundary rather than
-- preserving reference identity anyway - see ItemService.lua's own
-- identical NULL_SENTINEL for the same reasoning).
local NULL_SENTINEL = "__VEHICLE_REPOSITORY_NULL__"

-- enter marker element -> store row (id/name/spawnPositions)
local enterMarkers = {}
-- store zone elements -> store row - the separate drive-in-to-store zone.
-- Holds BOTH elements created for it: the actual colshape (invisible,
-- the real hit detector) and its visible marker twin (createMarker in
-- the exact same spot, purely so a player can see where to drive in -
-- MTA colshapes never render anything on their own). Only ever iterated
-- for reload()/onResourceStop's own destroyElement cleanup - deliberately
-- a different table from vehicleStoreZones below (these keys are
-- markers/colshapes, that one's keys are vehicles - sharing one table
-- would collide the two key spaces).
local storeZoneColshapes = {}
-- vehicle ELEMENT -> store row it's currently sitting inside the store
-- zone of (nil = not inside any store zone) - tracked for
-- sweepStoreZones's own grace-period cleanup (see below); storing itself
-- happens immediately on entry (onStoreZoneHit), this table isn't
-- consulted to trigger it.
local vehicleStoreZones = {}
-- player -> store row they're currently standing inside the ENTER marker of (panel open)
local playersInStore = {}
-- player -> getTickCount() of their last successful retrieve, for the cooldown
local lastRetrieveTick = {}
-- vehicle -> getTickCount() it was first seen sitting inside a store zone,
-- for STORE_ZONE_GRACE_MS - cleared once the vehicle leaves any zone.
local vehiclesInStoreZoneSince = {}

--- @param row table vehicles table row (id/model/mileage/... - as
--        returned by VehicleRepository.findByStoreId, JSON columns
--        already decoded)
-- @param owned boolean true if this is the requesting player's own PRIVATE
--        vehicle, OR any group vehicle the player is currently allowed to
--        use (see sendStoreItems' own GROUP-purpose branch) - purely a
--        "no lock icon in the panel" display flag, not a literal
--        ownership claim for the group case.
-- @return table a plain-data entry safe to send to the CEF panel
local function toEntry(row, owned)
    return {
        id = row.id,
        model = row.model,
        name = getVehicleNameFromModel(row.model) or ("Model " .. tostring(row.model)),
        mileage = row.mileage or 0,
        plate = row.plate,
        owned = owned,
    }
end

--- @param player element
-- @param vehicleId number a vehicles table row id
-- @return boolean true if `player` is carrying a VEHICLE_KEY item for
--         this specific vehicle - see gm_items/server/ItemService.lua's
--         own hasVehicleKey (already used the same way by
--         gm_vehicles_interaction to gate engine-start on a borrowed
--         vehicle - no <include resource="gm_items"> needed, exports work
--         across the resource boundary regardless, see that resource's
--         own meta.xml for the precedent).
local function playerHasKeyTo(player, vehicleId)
    local ok, hasKey = pcall(function()
        return exports.gm_items:itemServiceHasVehicleKey(player, vehicleId)
    end)
    return ok and hasKey == true
end

--- @param player element
-- @param vehicleId number
-- @param groupId number
-- @return boolean true if `player` may use this group vehicle (membership
--         + per-vehicle rank allowlist + on-duty-if-fraction) - same
--         gm_groups export VehicleInteractionService.lua's own
--         canStartEngine and gm_interactions' own hasVehicleKey use.
local function playerCanUseGroupVehicle(player, vehicleId, groupId)
    local ok, allowed = pcall(function()
        return exports.gm_groups:groupServiceCanUseVehicle(player, vehicleId, groupId)
    end)
    return ok and allowed == true
end

--- @param player element
-- @param store table the store row from enterMarkers
local function sendStoreItems(player, store)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    -- A GROUP-purpose lot lists every vehicle belonging to that group
    -- (any "owner_account_id", it's the creating admin, not meaningful
    -- for access - see Vehicle.lua's own group_id comment), filtered by
    -- groupServiceCanUseVehicle instead of the owned-or-key check below.
    -- A PRIVATE-purpose lot keeps its exact original behavior: own
    -- vehicles always show, someone else's only shows if `player` is
    -- carrying a VEHICLE_KEY item for that specific one (the same "you
    -- physically have the key" gate gm_vehicles_interaction already uses
    -- to let a borrowed vehicle's engine start - see playerHasKeyTo's own comment).
    VehicleBridge.call("findByStoreId", { store.id }, function(ok, rowsOrError)
        if not ok then
            Logger.error("VehicleStorageService", "Failed to load stored vehicles", { storeId = store.id, error = tostring(rowsOrError) })
            return
        end

        if not isElement(player) or playersInStore[player] ~= store then
            -- Left the marker (or disconnected) before the query came back.
            return
        end

        local entries = {}
        for _, row in ipairs(rowsOrError) do
            if store.purpose == Enums.VehicleStorePurpose.GROUP then
                if playerCanUseGroupVehicle(player, row.id, store.groupId) then
                    -- "owned" here just means "no lock icon in the panel" -
                    -- a group vehicle a member is allowed to use reads the
                    -- same as an owned one client-side, see toEntry's own
                    -- comment on that field's actual meaning.
                    entries[#entries + 1] = toEntry(row, true)
                end
            else
                local owned = row.owner_account_id == accountId
                if owned or playerHasKeyTo(player, row.id) then
                    entries[#entries + 1] = toEntry(row, owned)
                end
            end
        end

        triggerClientEvent(player, Events.VEHICLE_STORAGE_ITEMS_RECEIVED, resourceRoot, store.id, entries)
    end)
end

--- @param spawnPosition table { x, y, z, rx, ry, rz }
-- @return boolean true if no vehicle is currently sitting within
--         SPAWN_POSITION_CLEAR_RADIUS of this spot
local function isSpawnPositionClear(spawnPosition)
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        local vx, vy, vz = getElementPosition(vehicle)
        if getDistanceBetweenPoints3D(vx, vy, vz, spawnPosition.x, spawnPosition.y, spawnPosition.z) <= SPAWN_POSITION_CLEAR_RADIUS then
            return false
        end
    end
    return true
end

--- @param store table the store row (spawnPositions already normalized)
-- @return table|nil the first free spawn position, or nil if every one is occupied
local function findFreeSpawnPosition(store)
    for _, spawnPosition in ipairs(store.spawnPositions) do
        if isSpawnPositionClear(spawnPosition) then
            return spawnPosition
        end
    end
    return nil
end

addEvent(Events.VEHICLE_STORAGE_RETRIEVE, true)
addEventHandler(Events.VEHICLE_STORAGE_RETRIEVE, root, function(vehicleId)
    local player = client
    local store = playersInStore[player]
    if not store or type(vehicleId) ~= "number" then
        return
    end

    local now = getTickCount()
    local last = lastRetrieveTick[player]
    if last and now - last < RETRIEVE_COOLDOWN_MS then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Możesz odbierać pojazdy co kilka sekund." })
        return
    end

    if isPedInVehicle(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz opuścić pojazd, aby odebrać kolejny." })
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    VehicleBridge.call("findById", { vehicleId }, function(ok, rowOrError)
        if not ok or not rowOrError then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się wczytać pojazdu." })
            return
        end

        local row = rowOrError
        if row.store_id ~= store.id then
            -- Re-validated server-side - never trusts the panel's own
            -- belief that this vehicle is still here (see this event's
            -- own comment in Events.lua).
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Ten pojazd nie znajduje się już w tej przechowalni." })
            if isElement(player) and playersInStore[player] == store then
                sendStoreItems(player, store)
            end
            return
        end

        -- Re-validated server-side, same reasoning as the store_id check
        -- above - never trusts the panel's own belief that a vehicle is
        -- retrievable (the client could ask for any id, whether or not it
        -- was actually shown to it - see sendStoreItems' own filter).
        local owned
        if store.purpose == Enums.VehicleStorePurpose.GROUP then
            owned = playerCanUseGroupVehicle(player, row.id, store.groupId)
            if not owned then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz dostępu do tego pojazdu." })
                return
            end
        else
            owned = row.owner_account_id == accountId
            if not owned and not playerHasKeyTo(player, row.id) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz kluczyków do tego pojazdu." })
                return
            end
        end

        if not isElement(player) or playersInStore[player] ~= store then
            return
        end

        local spawnPosition = findFreeSpawnPosition(store)
        if not spawnPosition then
            NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Wszystkie miejsca odbioru są obecnie zajęte - spróbuj za chwilę." })
            return
        end

        VehicleBridge.call("update", { row.id, { store_id = NULL_SENTINEL } }, function(updateOk, affectedOrError)
            if not updateOk then
                Logger.error("VehicleStorageService", "Failed to clear store_id on retrieve", { id = row.id, error = tostring(affectedOrError) })
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się odebrać pojazdu." })
                return
            end

            local vehicle = VehicleService.spawnFromStore(row, spawnPosition)
            if not vehicle then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się stworzyć pojazdu. Zgłoś to administratorowi." })
                return
            end

            lastRetrieveTick[player] = now
            local vehicleName = getVehicleNameFromModel(row.model) or tostring(row.model)
            NotificationService.send(player, {
                type = Enums.NotificationType.SUCCESS,
                message = owned and ("Odebrano pojazd: " .. vehicleName) or ("Wypożyczono pojazd: " .. vehicleName),
            })

            -- Freshly spawned, so the driver seat is guaranteed free -
            -- unlike AdminCommands.lua's own teleportToVehicle (which
            -- teleports an admin to an arbitrary, possibly-occupied
            -- vehicle), no occupant check needed here.
            if isElement(player) then
                warpPedIntoVehicle(player, vehicle, 0)
            end

            if isElement(player) and playersInStore[player] == store then
                sendStoreItems(player, store)
            end
        end)
    end)
end)

--- Tries to store `vehicle` the instant it's driven onto a lot's
--- store_position zone - no keypress needed, driving in is the whole
--- interaction (mirrors the reference implementation this was ported
--- from, and the enter_position marker's own "walk in, panel just
--- opens" - no button there either). Silently does nothing if nobody's
--- driving it (an empty/pushed-in vehicle) or the driver seat is empty -
--- NOT an error case worth a notification, since a vehicle can enter this
--- zone without a player action at all (e.g. rolling in unattended).
-- @param vehicle vehicle
-- @param store table the store row this zone belongs to
local function tryStoreVehicle(vehicle, store)
    local driver = getVehicleOccupant(vehicle, 0)
    if not driver then
        return
    end

    local purpose = getElementData(vehicle, ElementData.Vehicle.PURPOSE)

    if store.purpose == Enums.VehicleStorePurpose.GROUP then
        -- A GROUP-purpose lot only accepts a vehicle belonging to THAT
        -- SAME group (not just any GROUP-purpose vehicle) - driven by
        -- anyone currently allowed to use it, not a literal "owner" (a
        -- group vehicle has no single owner - see Vehicle.lua's own
        -- group_id comment).
        if purpose ~= Enums.VehiclePurpose.GROUP then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Do tej przechowalni możesz schować tylko pojazdy grupy." })
            return
        end

        local vehicleGroupId = getElementData(vehicle, ElementData.Vehicle.GROUP_ID)
        if vehicleGroupId ~= store.groupId then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Ten pojazd nie należy do grupy tej przechowalni." })
            return
        end

        local vehicleId = getElementData(vehicle, ElementData.Vehicle.ID)
        if not playerCanUseGroupVehicle(driver, vehicleId, vehicleGroupId) then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Nie masz dostępu do tego pojazdu." })
            return
        end
    else
        if purpose ~= Enums.VehiclePurpose.PRIVATE then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Do przechowalni możesz schować tylko swój prywatny pojazd." })
            return
        end

        local ownerAccountId = getElementData(vehicle, ElementData.Vehicle.OWNER_ACCOUNT_ID)
        local accountId = PlayerService.getAccountId(driver)
        if not accountId or ownerAccountId ~= accountId then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Do przechowalni możesz schować tylko twoje pojazdy." })
            return
        end
    end

    VehicleService.storeVehicle(vehicle, store.id, function(ok)
        -- storeVehicle destroys `vehicle` on success (removed from the
        -- world) - destroyElement never fires onColShapeLeave for it, so
        -- both tracking tables need clearing explicitly here or they'd
        -- keep a dangling entry keyed by an element that no longer exists.
        vehiclesInStoreZoneSince[vehicle] = nil
        vehicleStoreZones[vehicle] = nil

        if not isElement(driver) then
            return
        end

        if not ok then
            NotificationService.send(driver, { type = Enums.NotificationType.ERROR, message = "Nie udało się schować pojazdu." })
            return
        end

        NotificationService.send(driver, { type = Enums.NotificationType.SUCCESS, message = "Schowałeś pojazd do przechowalni." })

        if playersInStore[driver] == store then
            sendStoreItems(driver, store)
        end
    end)
end

--- Gate for a GROUP-purpose lot's enter marker - the panel never opens at
--- all for someone with no access (not just an empty/filtered list once
--- it's already open), same "the marker acts like a wall" behavior
--- confirmed with the user. Sends the specific reason as a notification
--- either way - "not in this group at all" reads very differently from
--- "in the group but not currently on duty".
-- @param player element
-- @param store table
-- @return boolean true if the panel should open
local function checkGroupAccess(player, store)
    local ok, status = pcall(function()
        return exports.gm_groups:groupServiceGetMembershipStatus(player, store.groupId)
    end)
    if not ok then
        -- gm_groups unreachable - fail closed (deny), matching every other
        -- pcall'd cross-resource access check in this project (e.g.
        -- playerCanUseGroupVehicle's own `ok and allowed == true`).
        return false
    end

    if status == "ok" then
        return true
    end

    if status == "not_member" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Nie należysz do grupy, do której należy ta przechowalnia." })
    elseif status == "no_rank" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Lider nie ustawił tobie rangi w tej grupie." })
    elseif status == "not_on_duty" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Musisz być na służbie, aby korzystać z pojazdów tej grupy." })
    end
    return false
end

local function onEnterStore(store, player)
    if store.purpose == Enums.VehicleStorePurpose.GROUP and not checkGroupAccess(player, store) then
        return
    end

    playersInStore[player] = store
    triggerClientEvent(player, Events.VEHICLE_STORAGE_OPEN, resourceRoot, store.id, store.name, store.purpose)
    sendStoreItems(player, store)
end

local function onLeaveStore(player)
    if not playersInStore[player] then
        return
    end
    playersInStore[player] = nil
    triggerClientEvent(player, Events.VEHICLE_STORAGE_CLOSE, resourceRoot)
end

addEventHandler("onPlayerQuit", root, onLeaveStore)

-- Store-zone occupancy is tracked per (colshape, vehicle) pair via
-- onColShapeHit/Leave, not per-player - a vehicle can sit in the zone
-- with nobody in the driver seat (parked, driver walked off) and it
-- should still eventually get cleaned up, see the periodic sweep below.
-- tryStoreVehicle is also attempted right here, the instant the vehicle
-- enters - driving in IS the store action, no keypress needed (see that
-- function's own comment).
local function onStoreZoneHit(store)
    return function(hitElement, matchingDimension)
        if getElementType(hitElement) ~= "vehicle" or not matchingDimension then
            return
        end
        vehicleStoreZones[hitElement] = store
        if not vehiclesInStoreZoneSince[hitElement] then
            vehiclesInStoreZoneSince[hitElement] = getTickCount()
        end

        tryStoreVehicle(hitElement, store)
    end
end

local function onStoreZoneLeave(hitElement, matchingDimension)
    if getElementType(hitElement) ~= "vehicle" or not matchingDimension then
        return
    end
    vehicleStoreZones[hitElement] = nil
    vehiclesInStoreZoneSince[hitElement] = nil
end

--- Periodic sweep - any vehicle that's been sitting in a store zone
--- longer than STORE_ZONE_GRACE_MS gets destroyed, so a vehicle nobody
--- can/will actually store (not the owner's, not PRIVATE, or simply
--- abandoned there) doesn't block the drop-off spot forever. A
--- successful VehicleService.storeVehicle already removes the vehicle
--- from the world immediately and clears its own tracking entry (see
--- tryStoreVehicle), so this only ever catches vehicles that were never
--- actually stored (tryStoreVehicle's own checks rejected it, or nobody
--- was even driving it).
local function sweepStoreZones()
    local now = getTickCount()
    for vehicle, since in pairs(vehiclesInStoreZoneSince) do
        if not isElement(vehicle) then
            vehiclesInStoreZoneSince[vehicle] = nil
        elseif now - since >= STORE_ZONE_GRACE_MS then
            Logger.info("VehicleStorageService", "Destroyed a vehicle blocking a store zone", {
                model = getElementModel(vehicle),
            })
            vehiclesInStoreZoneSince[vehicle] = nil
            vehicleStoreZones[vehicle] = nil
            destroyElement(vehicle)
        end
    end
end

local sweepTimer = nil

--- Destroys every currently-spawned lot marker/zone and re-fetches
--- vehicle_stores from scratch, rebuilding them for the new set - called
--- once at startup and again any time AdminCommands.lua's own
--- store-management commands trigger Events.VEHICLE_STORE_RELOAD (see
--- that event's own comment), so an admin editing a lot never has to
--- manually restart this whole resource for it to take effect.
--- Also kicks any player currently standing inside a lot's enter marker
--- back out of the panel first (its marker element is about to be
--- destroyed and recreated, so it can never fire its own onMarkerLeave
--- for them).
-- @param callback function()|nil called once the reload finishes
local function reload(callback)
    for player in pairs(playersInStore) do
        onLeaveStore(player)
    end

    for marker in pairs(enterMarkers) do
        if isElement(marker) then
            destroyElement(marker)
        end
    end
    enterMarkers = {}

    for zone in pairs(storeZoneColshapes) do
        if isElement(zone) then
            destroyElement(zone)
        end
    end
    storeZoneColshapes = {}
    vehicleStoreZones = {}
    vehiclesInStoreZoneSince = {}

    if isTimer(sweepTimer) then
        killTimer(sweepTimer)
    end
    sweepTimer = setTimer(sweepStoreZones, STORE_ZONE_CHECK_INTERVAL_MS, 0)

    VehicleBridge.call("findAllVehicleStores", {}, function(ok, storesOrError)
        outputServerLog("[DEBUG VehicleStorageService] findAllVehicleStores ok=" .. tostring(ok) .. " count=" .. tostring(type(storesOrError) == "table" and #storesOrError or storesOrError))
        if not ok then
            Logger.error("VehicleStorageService", "Failed to load vehicle stores", { error = tostring(storesOrError) })
            if callback then callback() end
            return
        end

        for _, row in ipairs(storesOrError) do
            local enter = row.enter_position
            outputServerLog("[DEBUG VehicleStorageService] row id=" .. tostring(row.id) .. " enter=" .. tostring(enter) .. " type=" .. type(enter))
            if type(enter) == "table" and enter[1] and enter[2] and enter[3] then
                local store = {
                    id = row.id,
                    name = row.name,
                    purpose = row.purpose or Enums.VehicleStorePurpose.PRIVATE,
                    groupId = row.group_id,
                    spawnPositions = {},
                }

                for _, spawn in ipairs(row.spawn_positions or {}) do
                    store.spawnPositions[#store.spawnPositions + 1] = {
                        x = spawn[1], y = spawn[2], z = spawn[3],
                        rx = spawn[4] or 0, ry = spawn[5] or 0, rz = spawn[6] or 0,
                    }
                end

                if #store.spawnPositions == 0 then
                    Logger.warn("VehicleStorageService", "Vehicle store has no spawn positions, skipping", { id = row.id })
                else
                    -- Gold for a GROUP-purpose lot, the existing blue for
                    -- PRIVATE - purely cosmetic, lets a player tell the two
                    -- apart at a glance before even walking up.
                    local markerColor = store.purpose == Enums.VehicleStorePurpose.GROUP
                        and { 242, 184, 74 }
                        or { 52, 152, 219 }
                    local marker = createMarker(enter[1], enter[2], enter[3] - 0.9, "cylinder", 5, markerColor[1], markerColor[2], markerColor[3], 100)
                    setElementData(marker, "text", row.name)
                    enterMarkers[marker] = store

                    addEventHandler("onMarkerHit", marker, function(hitElement, matchingDimension)
                        if getElementType(hitElement) ~= "player" or not matchingDimension then
                            return
                        end
                        onEnterStore(store, hitElement)
                    end)

                    addEventHandler("onMarkerLeave", marker, function(hitElement, matchingDimension)
                        if getElementType(hitElement) ~= "player" or not matchingDimension then
                            return
                        end
                        onLeaveStore(hitElement)
                    end)

                    local storePos = row.store_position
                    if type(storePos) == "table" and storePos[1] and storePos[2] and storePos[3] then
                        -- The colshape (createColSphere) is the actual hit
                        -- detector - invisible on its own, MTA colshapes
                        -- never render anything. This visible marker sits
                        -- in the exact same spot purely so a player can
                        -- SEE where to drive in - green (not the enter
                        -- marker's blue) so the two read as different
                        -- actions at a glance.
                        local storeMarker = createMarker(storePos[1], storePos[2], storePos[3] - 0.9, "cylinder", 4, 46, 204, 113, 100)
                        setElementData(storeMarker, "text", "Schowaj pojazd")
                        storeZoneColshapes[storeMarker] = store

                        local zone = createColSphere(storePos[1], storePos[2], storePos[3], 4)
                        storeZoneColshapes[zone] = store

                        addEventHandler("onColShapeHit", zone, onStoreZoneHit(store))
                        addEventHandler("onColShapeLeave", zone, onStoreZoneLeave)
                    end
                end
            end
        end

        Logger.info("VehicleStorageService", "Loaded vehicle stores", { count = #storesOrError })
        if callback then callback() end
    end)
end

addEvent(Events.VEHICLE_STORE_RELOAD, true)
addEventHandler(Events.VEHICLE_STORE_RELOAD, root, function()
    reload()
end)

addEventHandler("onResourceStart", resourceRoot, function()
    -- Same DATABASE_READY/Schema.isMigrated() gotcha VehicleService.lua's
    -- own onResourceStart documents.
    print('start')
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    outputServerLog("[DEBUG VehicleStorageService] onResourceStart migratedOk=" .. tostring(migratedOk) .. " migrated=" .. tostring(migrated))
    if migratedOk and migrated then
        print('migrated')
        reload()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, reload)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for marker in pairs(enterMarkers) do
        if isElement(marker) then
            destroyElement(marker)
        end
    end
    enterMarkers = {}

    for zone in pairs(storeZoneColshapes) do
        if isElement(zone) then
            destroyElement(zone)
        end
    end
    storeZoneColshapes = {}

    if isTimer(sweepTimer) then
        killTimer(sweepTimer)
    end
end)
