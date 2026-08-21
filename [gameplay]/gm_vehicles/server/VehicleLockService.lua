-- Lock/unlock toggle with a real-key-fob-style light signal (headlights
-- flash: 1x on unlock, 2x on lock) - a plain MTA native
-- (setVehicleLocked) wrapped with the flash timing, exported so other
-- resources (gm_interactions' "vehicle:toggleLock" world interaction,
-- gm_items' ItemUseHandlers.lua's VEHICLE_KEY "use" handler) get the
-- signal for free instead of each reimplementing it, and so the flash
-- logic lives in exactly one place. A separate file from
-- VehicleService.lua (which owns persistent-vehicle spawn/save/database
-- state) since this works on ANY vehicle, the same "doesn't depend on
-- gm_vehicles' own persistence" scope VehicleInteractionService.lua's own
-- module comment already establishes for transient toggles.
VehicleLockService = VehicleLockService or {}

local FLASH_ON_MS = 150
local FLASH_GAP_MS = 150

-- vehicle -> true while a flash sequence owns setVehicleOverrideLights for
-- it - a second toggleVehicleLock call mid-sequence (e.g. mashing the
-- interaction key) skips its own flash rather than fighting the first
-- sequence's own restore-to-original-override at the end.
local flashing = {}

--- Flashes `vehicle`'s headlights `times` times, then restores whatever
--- light override was active before the flash started.
-- @param vehicle vehicle
-- @param times number
local function flashLights(vehicle, times)
    if flashing[vehicle] then
        return
    end
    flashing[vehicle] = true

    local originalOverride = getVehicleOverrideLights(vehicle)

    local function restore()
        flashing[vehicle] = nil
        if isElement(vehicle) then
            setVehicleOverrideLights(vehicle, originalOverride)
        end
    end

    local function flashOnce(remaining)
        if not isElement(vehicle) then
            flashing[vehicle] = nil
            return
        end

        setVehicleOverrideLights(vehicle, 2)
        setTimer(function()
            if not isElement(vehicle) then
                flashing[vehicle] = nil
                return
            end

            setVehicleOverrideLights(vehicle, 1)

            if remaining > 1 then
                setTimer(flashOnce, FLASH_GAP_MS, 1, remaining - 1)
            else
                setTimer(restore, FLASH_GAP_MS, 1)
            end
        end, FLASH_ON_MS, 1)
    end

    flashOnce(times)
end

-- Door indices 2-5 are the actual entry doors (front-left/front-right/
-- rear-left/rear-right) - see https://wiki.multitheftauto.com/wiki/GetVehicleDoorOpenRatio /
-- SetVehicleDoorOpenRatio. 0 (hood) and 1 (trunk) are deliberately
-- excluded: setVehicleLocked alone doesn't stop a player walking through
-- a door that's already open, but a hood/trunk being open doesn't let
-- anyone INTO the vehicle, so forcing those shut too would just be a
-- cosmetic side effect with no actual security purpose.
local ENTRY_DOOR_INDICES = { 2, 3, 4, 5 }
-- setVehicleDoorOpenRatio eases from the door's current ratio to this one
-- over DOOR_CLOSE_ANIMATION_MS instead of snapping shut instantly the way
-- setVehicleDoorState does.
local DOOR_CLOSE_ANIMATION_MS = 400

--- Eases every open entry door shut - setVehicleLocked alone leaves an
--- already-open door open, letting anyone still walk straight in despite
--- the vehicle now being locked.
-- @param vehicle vehicle
local function closeOpenDoors(vehicle)
    for _, doorIndex in ipairs(ENTRY_DOOR_INDICES) do
        if getVehicleDoorOpenRatio(vehicle, doorIndex) > 0 then
            setVehicleDoorOpenRatio(vehicle, doorIndex, 0, DOOR_CLOSE_ANIMATION_MS)
        end
    end
end

--- Toggles `vehicle`'s lock state and flashes its headlights to signal
--- the new state (1x = now unlocked, 2x = now locked) - same convention
--- real vehicle key fobs use. Locking also force-closes any open entry
--- door (see closeOpenDoors's own comment).
-- @param vehicle vehicle
-- @return boolean the new locked state
VehicleLockService.toggle = function(vehicle)
    local nowLocked = not isVehicleLocked(vehicle)
    setVehicleLocked(vehicle, nowLocked)
    if nowLocked then
        closeOpenDoors(vehicle)
    end
    flashLights(vehicle, nowLocked and 2 or 1)
    return nowLocked
end

function toggleVehicleLock(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then
        return nil
    end
    return VehicleLockService.toggle(vehicle)
end

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) == "vehicle" then
        flashing[source] = nil
    end
end)
