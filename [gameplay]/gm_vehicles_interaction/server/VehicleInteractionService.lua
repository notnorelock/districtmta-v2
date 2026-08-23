-- Radial vehicle interaction menu (left Shift, held, while driving) -
-- server side. Only toggles what's actually already synced/server-
-- authoritative in MTA: engine, headlight override, door lock, and a
-- handbrake modeled as setElementFrozen (see https://wiki.multitheftauto.com/wiki/IsElementFrozen -
-- shared server+client function, already used elsewhere in gm_vehicles
-- for a freshly-spawned/loaded vehicle - see VehicleService.lua's
-- spawnFromRow). A frozen vehicle doesn't just lose engine power/brake
-- like GTA's own handbrake (space bar) - it's fully immobile, immune to
-- physics/collisions pushing it, which is the point: a real parking
-- brake a passenger can't accidentally roll away from. The menu itself
-- (which options exist, selection/scroll UI) is entirely client-side
-- (VehicleInteractionState.lua) - this file only ever reacts to an
-- explicit toggle request and re-validates the requester before touching
-- anything, exactly like every other server-authoritative toggle in this
-- project (radio station change, voice mode cycle).
--
-- A separate resource from gm_vehicles on purpose - this only ever
-- touches transient, already-synced MTA vehicle state (engine/lights/
-- lock/frozen), never the database, and works on ANY vehicle the local
-- player happens to be driving (gm_vehicles's own persistent vehicles,
-- gm_roleplay's /veh temporary ones, or anything else) - it doesn't
-- depend on gm_vehicles at all, so it doesn't need to be coupled to it or
-- restart together with it.
VehicleInteractionService = VehicleInteractionService or {}

--- @param vehicle vehicle
-- @return table { engine: boolean, lights: boolean, lock: boolean, handbrake: boolean }
local function stateOf(vehicle)
    return {
        engine = getVehicleEngineState(vehicle),
        -- Modeled as a plain on/off toggle (override = 2/"force on" vs
        -- 0/"no override") - MTA's real 3-state override (no override/
        -- force off/force on) is more than this menu needs to expose.
        lights = getVehicleOverrideLights(vehicle) == 2,
        lock = isVehicleLocked(vehicle),
        handbrake = isElementFrozen(vehicle),
    }
end

--- @param player element
-- @return vehicle|nil the vehicle `player` is driving, nil if not a driver
local function drivenVehicleOf(player)
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle and getVehicleController(vehicle) == player then
        return vehicle
    end
    return nil
end

--- Pushes `vehicle`'s current toggle state to every current occupant.
-- @param vehicle vehicle
-- @param action string|nil one of "engine"/"lights"/"lock"/"handbrake" -
--        the action that just changed, nil when seeding initial state
--        (e.g. menu open)
local function broadcastState(vehicle, action)
    local state = stateOf(vehicle)
    for _, occupant in pairs(getVehicleOccupants(vehicle)) do
        triggerClientEvent(occupant, Events.PUSH_VEHICLE_INTERACTION_STATE, occupant, action, state)
    end
end

-- Only gm_vehicles' own persistent vehicles carry ElementData.Vehicle.ID
-- (set by VehicleService.lua's spawnFromRow) - a temporary /veh spawn
-- (gm_roleplay) or any other vehicle this resource works on regardless
-- (see this file's own module comment on why it isn't coupled to
-- gm_vehicles) has no such id and therefore no gm_items key concept to
-- check, so those are left unrestricted rather than treated as
-- "no key, deny."
-- @param player element
-- @param vehicle vehicle
-- @return boolean
local function canStartEngine(player, vehicle)
    local vehicleId = getElementData(vehicle, ElementData.Vehicle.ID)
    if not vehicleId then
        return true
    end

    -- A GROUP-purpose vehicle doesn't use the VEHICLE_KEY item system at
    -- all - access is membership + per-vehicle rank allowlist (+ on-duty
    -- for a fraction-type group) instead, decided by gm_groups' own
    -- groupServiceCanUseVehicle export (synchronous, backed by an
    -- in-memory cache - see MembershipCache.lua's own module comment on
    -- why this doesn't need a DB round trip here).
    local groupId = getElementData(vehicle, ElementData.Vehicle.GROUP_ID)
    if groupId then
        local ok, allowed = pcall(function()
            return exports.gm_groups:groupServiceCanUseVehicle(player, vehicleId, groupId)
        end)
        return ok and allowed == true
    end

    local ok, hasKey = pcall(function()
        return exports.gm_items:itemServiceHasVehicleKey(player, vehicleId)
    end)
    return ok and hasKey == true
end

-- Blocks even GETTING IN as the driver of a group vehicle you have no
-- access to - not just starting its engine (canStartEngine above already
-- covers "got in some other way, e.g. an unlocked/already-open vehicle,
-- climbed over from a passenger seat"). Passenger seats (seat ~= 0) are
-- always left alone - a player with duty/rank access can be driven around
-- by someone who lacks it, and someone with no access at all should still
-- be able to ride along once already inside via a driver who does. Only
-- affects gm_vehicles' own GROUP-purpose vehicles (ElementData.Vehicle.GROUP_ID) -
-- everything else (private/public/temporary /veh spawns) is unrestricted here.
addEventHandler("onVehicleStartEnter", root, function(enteringPlayer, seat)
    if seat ~= 0 then
        return
    end

    local vehicleId = getElementData(source, ElementData.Vehicle.ID)
    local groupId = getElementData(source, ElementData.Vehicle.GROUP_ID)
    if not vehicleId or not groupId then
        return
    end

    local ok, allowed = pcall(function()
        return exports.gm_groups:groupServiceCanUseVehicle(enteringPlayer, vehicleId, groupId)
    end)
    if ok and allowed == true then
        return
    end

    local nameOk, groupName = pcall(function() return exports.gm_groups:groupServiceGetGroupName(groupId) end)
    local label = (nameOk and groupName) and groupName or "grupy"
    NotificationService.send(enteringPlayer, {
        type = Enums.NotificationType.ERROR,
        message = "Ten pojazd należy do grupy '" .. label .. "'. Nie masz uprawnień, aby nim kierować.",
    })
    cancelEvent()
end)

addEvent(Events.VEHICLE_INTERACTION_TOGGLE, true)
addEventHandler(Events.VEHICLE_INTERACTION_TOGGLE, root, function(action)
    local player = client
    local vehicle = drivenVehicleOf(player)
    if not vehicle then
        return
    end

    if action == "engine" then
        -- Starting the engine (not stopping it - a driver who already
        -- has it running, e.g. one who legitimately started it themself
        -- and is now just passing the wheel, isn't re-checked to turn it
        -- back off) requires actually carrying this vehicle's key -
        -- otherwise anyone who ends up in the driver seat (an unlocked/
        -- already-open vehicle, a passenger who climbed over) could
        -- start and drive off a vehicle they don't own.
        local wantsOn = not getVehicleEngineState(vehicle)
        if wantsOn and not canStartEngine(player, vehicle) then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz kluczyków do tego pojazdu." })
            return
        end
        setVehicleEngineState(vehicle, wantsOn)
    elseif action == "lights" then
        local wantsOn = getVehicleOverrideLights(vehicle) ~= 2
        setVehicleOverrideLights(vehicle, wantsOn and 2 or 1)
    elseif action == "lock" then
        setVehicleLocked(vehicle, not isVehicleLocked(vehicle))
    elseif action == "handbrake" then
        setElementFrozen(vehicle, not isElementFrozen(vehicle))
    else
        return
    end

    broadcastState(vehicle, action)
end)

addEvent(Events.VEHICLE_INTERACTION_QUERY, true)
addEventHandler(Events.VEHICLE_INTERACTION_QUERY, root, function()
    local vehicle = drivenVehicleOf(client)
    if not vehicle then
        return
    end
    triggerClientEvent(client, Events.PUSH_VEHICLE_INTERACTION_STATE, client, nil, stateOf(vehicle))
end)
