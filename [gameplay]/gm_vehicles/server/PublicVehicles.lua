-- Public vehicles: free, temporary, NOT persisted to the database (see
-- Enums.VehiclePurpose's own module comment) - a fixed list of spawn
-- points defined right here in code. Ported from the reference
-- implementation's own public-vehicle behavior: only the driver seat is
-- exclusive (another player can still ride as a passenger), a second
-- player trying to take the driver seat while it's occupied is rejected,
-- and the vehicle despawns 60 seconds after the driver leaves if nobody
-- gets back in (respawns fresh at its original spot right away - see
-- despawnAndRespawn below). No 3D "occupied by X" floating label
-- (the reference used a custom pd_3dtext element this project doesn't
-- have) - purely a placeholder for later if wanted.
PublicVehicles = PublicVehicles or {}

local VACATED_DESPAWN_MS = 60000

-- Add entries here as real spawn points are decided: { model, x, y, z, rx, ry, rz }.
local SPAWN_POINTS = {
    -- { model = 411, x = 1959.3, y = -1714.9, z = 13.5, rx = 0, ry = 0, rz = 180 },
}

-- vehicle element -> { spawnPoint, driver = player|nil, vacatedTimer = timer|nil }
local activeVehicles = {}

local function spawnAt(spawnPoint)
    local vehicle = createVehicle(spawnPoint.model, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.rx or 0, spawnPoint.ry or 0, spawnPoint.rz or 0)
    if not vehicle then
        Logger.error("PublicVehicles", "createVehicle failed for a public spawn point", { model = spawnPoint.model })
        return nil
    end

    activeVehicles[vehicle] = { spawnPoint = spawnPoint }

    setElementData(vehicle, ElementData.Vehicle.PURPOSE, Enums.VehiclePurpose.PUBLIC)
    setVehicleRespawnPosition(vehicle, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.rx or 0, spawnPoint.ry or 0, spawnPoint.rz or 0)

    return vehicle
end

local function despawnAndRespawn(vehicle)
    local entry = activeVehicles[vehicle]
    if not entry then
        return
    end

    activeVehicles[vehicle] = nil
    if isElement(vehicle) then
        destroyElement(vehicle)
    end

    spawnAt(entry.spawnPoint)
end

addEventHandler("onVehicleStartEnter", root, function(enteringPlayer, seat)
    local entry = activeVehicles[source]
    if not entry or seat ~= 0 then
        return
    end

    if entry.driver and entry.driver ~= enteringPlayer and isElement(entry.driver) then
        outputChatBox("Ten pojazd publiczny jest zajęty przez innego gracza.", enteringPlayer, 255, 80, 80)
        cancelEvent()
    end
end)

addEventHandler("onVehicleEnter", root, function(player, seat)
    local entry = activeVehicles[source]
    if not entry or seat ~= 0 then
        return
    end

    if entry.vacatedTimer and isTimer(entry.vacatedTimer) then
        killTimer(entry.vacatedTimer)
    end
    entry.vacatedTimer = nil
    entry.driver = player
end)

addEventHandler("onVehicleExit", root, function(player, seat)
    local entry = activeVehicles[source]
    if not entry or seat ~= 0 or entry.driver ~= player then
        return
    end

    local vehicle = source
    entry.driver = nil
    entry.vacatedTimer = setTimer(function()
        despawnAndRespawn(vehicle)
    end, VACATED_DESPAWN_MS, 1)
end)

addEventHandler("onElementDestroy", root, function()
    activeVehicles[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, spawnPoint in ipairs(SPAWN_POINTS) do
        spawnAt(spawnPoint)
    end

    if #SPAWN_POINTS > 0 then
        Logger.info("PublicVehicles", "Spawned public vehicles", { count = #SPAWN_POINTS })
    end
end)
