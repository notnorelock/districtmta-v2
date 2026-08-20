-- Private (persistent, database-backed) vehicles: spawning a saved row
-- into the world, saving world state back, and periodic autosave. Public
-- vehicles are a separate, purely scripted concept - see PublicVehicles.lua.
-- Ported from an older, unrelated project's reference implementation, cut
-- down to what this project actually has: PRIVATE ownership only
-- (Enums.VehiclePurpose.PRIVATE), owner = account, not character (no
-- character-select system exists yet - see docs project memory). GROUP/
-- EVENT/EXCHANGE/SHOP/RENT purposes, tuning workshops, the vehicle
-- exchange, and vehicle sharing all do NOT exist in this project and are
-- deliberately not ported - only the fields needed to round-trip a
-- vehicle's saved state (tuning/doors/lights/panels/wheels/colors/plate/
-- fuel/mileage/last drivers) are kept, unused until something reads them.
VehicleService = VehicleService or {}

local SAVE_INTERVAL_MS = 30000
local DEFAULT_HEALTH = 1000
local DEFAULT_FUEL = 100
local DEFAULT_MAX_FUEL = 100
local MAX_LAST_DRIVERS = 5

-- vehicle element -> database row id, for every world vehicle this
-- resource created (not other resources' temporary /veh spawns).
local vehicleIds = {}

--- @param vehicle vehicle
-- @return number|nil the vehicles.id row this vehicle element was created from
VehicleService.idOf = function(vehicle)
    return vehicleIds[vehicle]
end

--- @param row table a vehicles table row (JSON columns already decoded by VehicleRepository)
-- @return vehicle|nil the spawned, frozen-engine-off world vehicle
local function spawnFromRow(row)
    local position = row.position
    local rotation = row.rotation
    if type(position) ~= "table" or type(rotation) ~= "table" then
        Logger.error("VehicleService", "Vehicle row has malformed position/rotation, skipping spawn", { id = row.id })
        return nil
    end

    local vehicle = createVehicle(row.model, position[1], position[2], position[3], rotation[1], rotation[2], rotation[3])
    if not vehicle then
        Logger.error("VehicleService", "createVehicle failed", { id = row.id, model = row.model })
        return nil
    end

    vehicleIds[vehicle] = row.id

    setElementData(vehicle, ElementData.Vehicle.ID, row.id)
    setElementData(vehicle, ElementData.Vehicle.PURPOSE, row.purpose)
    setElementData(vehicle, ElementData.Vehicle.OWNER_ACCOUNT_ID, row.owner_account_id)

    setElementHealth(vehicle, math.max(1, row.health or DEFAULT_HEALTH))
    setVehicleLocked(vehicle, row.locked == true or row.locked == 1)

    if row.plate and row.plate ~= "" then
        setVehiclePlateText(vehicle, row.plate)
    end

    if type(row.doors) == "table" then
        for doorIndex, state in pairs(row.doors) do
            setVehicleDoorState(vehicle, tonumber(doorIndex), tonumber(state))
        end
    end

    if type(row.lights) == "table" then
        if type(row.lights.state) == "table" then
            for lightIndex, state in pairs(row.lights.state) do
                setVehicleLightState(vehicle, tonumber(lightIndex), tonumber(state))
            end
        end
        if type(row.lights.color) == "table" then
            setVehicleHeadLightColor(vehicle, row.lights.color[1], row.lights.color[2], row.lights.color[3])
        end
    end

    if type(row.panels) == "table" then
        for panelIndex, state in pairs(row.panels) do
            setVehiclePanelState(vehicle, tonumber(panelIndex), tonumber(state))
        end
    end

    if type(row.wheels) == "table" then
        setVehicleWheelStates(vehicle, row.wheels[1], row.wheels[2], row.wheels[3], row.wheels[4])
    end

    if type(row.color) == "table" and #row.color >= 12 then
        setVehicleColor(vehicle, row.color[1], row.color[2], row.color[3], row.color[4], row.color[5], row.color[6],
            row.color[7], row.color[8], row.color[9], row.color[10], row.color[11], row.color[12])
    end

    if type(row.upgrades) == "table" and type(row.upgrades.parts) == "table" then
        for _, upgrade in pairs(row.upgrades.parts) do
            addVehicleUpgrade(vehicle, upgrade)
        end
    end
    -- upgrades.neons/paintjob/engine: no in-game system reads/writes
    -- these yet (no tuning workshop - see this file's own module
    -- comment) - kept on the row as opaque data, round-tripped through
    -- save/spawn without being interpreted here. Cached now so
    -- currentStateOf's next save doesn't silently drop them.
    if type(row.upgrades) == "table" then
        setElementData(vehicle, ElementData.Vehicle.UPGRADES_CACHE, row.upgrades)
    end
    if type(row.last_drivers) == "table" then
        setElementData(vehicle, ElementData.Vehicle.LAST_DRIVERS_CACHE, row.last_drivers)
    end

    setElementInterior(vehicle, row.interior or 0)
    setElementDimension(vehicle, row.dimension or 0)
    setVehicleRespawnPosition(vehicle, position[1], position[2], position[3], rotation[1], rotation[2], rotation[3])

    setVehicleEngineState(vehicle, false)
    setElementFrozen(vehicle, true)

    return vehicle
end

--- @param player element
-- @param model number
-- @param ownerAccountId number
-- @param callback function(vehicle: vehicle|nil)
VehicleService.createPrivate = function(player, model, ownerAccountId, callback)
    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)

    VehicleBridge.call("create", {{
        purpose = Enums.VehiclePurpose.PRIVATE,
        model = model,
        position = { x, y, z },
        rotation = { rx, ry, rz },
        health = DEFAULT_HEALTH,
        mileage = 0,
        fuel = DEFAULT_FUEL,
        max_fuel = DEFAULT_MAX_FUEL,
        owner_account_id = ownerAccountId,
        locked = true,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
    }}, function(ok, rowOrError)
        if not ok then
            Logger.error("VehicleService", "Failed to create vehicle row", { error = tostring(rowOrError) })
            callback(nil)
            return
        end

        callback(spawnFromRow(rowOrError))
    end)
end

--- Serializes `vehicle`'s current world state back into the shape
--- VehicleRepository.update expects (JSON columns as real Lua tables -
--- VehicleRepository itself encodes them before they reach the database).
-- @param vehicle vehicle
-- @return table
local function currentStateOf(vehicle)
    local x, y, z = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)

    local doors = {}
    for doorIndex = 0, 5 do
        doors[doorIndex] = getVehicleDoorState(vehicle, doorIndex)
    end

    local lightState = {}
    for lightIndex = 0, 3 do
        lightState[lightIndex] = getVehicleLightState(vehicle, lightIndex)
    end
    local headR, headG, headB = getVehicleHeadLightColor(vehicle)

    local panels = {}
    for panelIndex = 0, 6 do
        panels[panelIndex] = getVehiclePanelState(vehicle, panelIndex)
    end

    local w1, w2, w3, w4 = getVehicleWheelStates(vehicle)

    local r1, g1, b1, r2, g2, b2, r3, g3, b3, r4, g4, b4 = getVehicleColor(vehicle, true)

    local existingUpgrades = getElementData(vehicle, ElementData.Vehicle.UPGRADES_CACHE)
    local upgrades = type(existingUpgrades) == "table" and existingUpgrades or {}
    upgrades.parts = getVehicleUpgrades(vehicle)

    local lastDrivers = getElementData(vehicle, ElementData.Vehicle.LAST_DRIVERS_CACHE)
    if type(lastDrivers) ~= "table" then
        lastDrivers = {}
    end

    return {
        position = { x, y, z },
        rotation = { rx, ry, rz },
        health = getElementHealth(vehicle),
        locked = isVehicleLocked(vehicle),
        upgrades = upgrades,
        doors = doors,
        lights = { state = lightState, color = { headR, headG, headB } },
        panels = panels,
        wheels = { w1, w2, w3, w4 },
        color = { r1, g1, b1, r2, g2, b2, r3, g3, b3, r4, g4, b4 },
        plate = getVehiclePlateText(vehicle),
        interior = getElementInterior(vehicle),
        dimension = getElementDimension(vehicle),
        last_drivers = lastDrivers,
    }
end

--- @param vehicle vehicle
-- @param callback function(ok: boolean)|nil
VehicleService.save = function(vehicle, callback)
    local id = vehicleIds[vehicle]
    if not id then
        if callback then callback(false) end
        return
    end

    VehicleBridge.call("update", { id, currentStateOf(vehicle) }, function(ok, affectedOrError)
        if not ok then
            Logger.error("VehicleService", "Vehicle save failed", { id = id, error = tostring(affectedOrError) })
        end
        if callback then callback(ok) end
    end)
end

--- Records `player` as this vehicle's most recent driver (most recent
--- last) - capped at MAX_LAST_DRIVERS entries, oldest dropped first.
-- @param vehicle vehicle
-- @param player element
VehicleService.recordDriver = function(vehicle, player)
    local id = vehicleIds[vehicle]
    if not id then
        return
    end

    local lastDrivers = getElementData(vehicle, ElementData.Vehicle.LAST_DRIVERS_CACHE)
    lastDrivers = type(lastDrivers) == "table" and lastDrivers or {}

    lastDrivers[#lastDrivers + 1] = { name = getPlayerName(player) }
    while #lastDrivers > MAX_LAST_DRIVERS do
        table.remove(lastDrivers, 1)
    end

    setElementData(vehicle, ElementData.Vehicle.LAST_DRIVERS_CACHE, lastDrivers)
end

--- Saves every private vehicle this resource is tracking.
VehicleService.saveAll = function()
    for vehicle in pairs(vehicleIds) do
        if isElement(vehicle) then
            VehicleService.save(vehicle)
        end
    end
end

-- Records the driver and saves immediately on exit (not just the
-- periodic autosave) so a vehicle's last-known state survives a crash
-- between autosave ticks, matching the reference implementation's own
-- save-on-exit behavior.
addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat == 0 and vehicleIds[source] then
        VehicleService.recordDriver(source, player)
    end
end)

addEventHandler("onVehicleExit", root, function(player, seat)
    if seat == 0 and vehicleIds[source] then
        VehicleService.save(source)
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function loadAllPrivate()
        VehicleBridge.call("findAllPrivate", {}, function(ok, rowsOrError)
            if not ok then
                Logger.error("VehicleService", "Failed to load private vehicles", { error = tostring(rowsOrError) })
                return
            end

            for _, row in ipairs(rowsOrError) do
                spawnFromRow(row)
            end

            Logger.info("VehicleService", "Loaded private vehicles", { count = #rowsOrError })
        end)
    end

    -- Same DATABASE_READY/Schema.isMigrated() gotcha documented in
    -- docs/DatabaseContract.md - core (a resource that started earlier in
    -- core_bootstrap's chain) may still be mid-migration when THIS
    -- resource's onResourceStart fires.
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    if migratedOk and migrated then
        loadAllPrivate()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, loadAllPrivate)
    end

    setTimer(VehicleService.saveAll, SAVE_INTERVAL_MS, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    VehicleService.saveAll()
end)

addEventHandler("onElementDestroy", root, function()
    if vehicleIds[source] then
        vehicleIds[source] = nil
    end
end)
