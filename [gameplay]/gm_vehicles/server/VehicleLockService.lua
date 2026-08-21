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

--- Toggles `vehicle`'s lock state and flashes its headlights to signal
--- the new state (1x = now unlocked, 2x = now locked) - same convention
--- real vehicle key fobs use.
-- @param vehicle vehicle
-- @return boolean the new locked state
VehicleLockService.toggle = function(vehicle)
    local nowLocked = not isVehicleLocked(vehicle)
    setVehicleLocked(vehicle, nowLocked)
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
