-- Vehicle radio client: driver-only scroll/R controls, playing the
-- current station's stream, and pushing station-change info into the CEF
-- HUD (see the RadioCard component on the frontend) instead of the old
-- dxDraw text banner - the real HUD lives in CEF, dxGUI/dxDraw is
-- reserved for small one-off admin tools (same reasoning as gm_voice's
-- nearby-speaker indicator).
RadioState = RadioState or {}

local VOLUME = 0.6
local SCROLL_DELAY_MS = 300
local HIDE_CARD_DELAY_MS = 6000

local sound = nil
local lastScrollTick = 0
local hideCardTimer = nil

--- @param player element
-- @return boolean true if `player` is in the driver seat of a vehicle
local function isDriving(player)
    -- getPedOccupiedVehicle returns false (not nil) when the ped isn't in
    -- any vehicle - `vehicle ~= nil` is true even for false, so
    -- getVehicleController(false) was still being called ("Bad argument @
    -- 'getVehicleController' [Expected vehicle at argument 1, got
    -- boolean]") every time this ran while on foot. isElement() is the
    -- correct truthiness check for a value that might be false, an
    -- element, or (in principle) nil.
    local vehicle = getPedOccupiedVehicle(player)
    return isElement(vehicle) and getVehicleController(vehicle) == player
end

local function requestChangeStation(next)
    if isCursorShowing() then
        return
    end
    if getTickCount() < lastScrollTick + SCROLL_DELAY_MS then
        return
    end
    if not isDriving(localPlayer) then
        return
    end

    -- gm_vehicles_interaction's radial interaction menu (left Shift,
    -- held, while driving) also uses scroll to move its own selection -
    -- without this check, scrolling to pick a menu option also cycled
    -- the radio station underneath it. pcall guards against
    -- gm_vehicles_interaction not being up yet/restarted independently -
    -- "not open" is the safe default, same as every other
    -- exports.X:fn() call in this project.
    local menuOk, menuOpen = pcall(function() return exports.gm_vehicles_interaction:vehicleInteractionIsMenuOpen() end)
    if menuOk and menuOpen then
        return
    end

    lastScrollTick = getTickCount()
    triggerServerEvent(Events.RADIO_CHANGE_STATION, resourceRoot, next)
end

local function scrollStation(key)
    if key == "mouse_wheel_up" then
        requestChangeStation(true)
    elseif key == "mouse_wheel_down" then
        requestChangeStation(false)
    end
end

--- Stops and forgets the current stream, if any.
local function stopSound()
    if sound and isElement(sound) then
        destroyElement(sound)
    end
    sound = nil
end

--- Pushes the current station (or "off") into the CEF HUD, and schedules
--- auto-hide a few seconds later - the card itself is a "just changed"
--- notification, not a permanent fixture (matches the old dxDraw
--- version's RADIO_FADE_TIME banner behavior). A station switching off
--- still shows the card briefly (with an "off" message) instead of
--- vanishing silently - otherwise scrolling past the last station into
--- "off" gives no feedback at all that anything happened.
--
-- Always wrapped in a { station, loading } table, and `station` is
-- normalized to `station or "off"` before going in - exports.X:fn(a, nil)
-- drops a literal nil argument entirely (MTA's export call marshalling
-- doesn't distinguish "nil argument" from "argument omitted"), so
-- UI.pushEvent's `data` would receive nothing at all and
-- toJsonValue(nil) blows up on the other side. Wrapping in a table isn't
-- enough by itself either: `{ station = nil }` doesn't create a `station`
-- key at all (assigning nil to a table field removes/never creates it),
-- so toJSON would emit `{}` instead of `{"station":"off"}` - the frontend
-- would then see `undefined`, not the sentinel it checks for.
-- @param station table|nil nil means "off"
-- @param loading boolean|nil true while playSound has been called but
--        onClientSoundStream hasn't confirmed success yet - drives the
--        cover spinner on the frontend.
-- @param hideImmediately boolean|nil true to hide the card with no delay
--        (vehicle exit) instead of showing an "off" state first.
local function pushCardState(station, loading, hideImmediately)
    if isTimer(hideCardTimer) then
        killTimer(hideCardTimer)
        hideCardTimer = nil
    end

    if not station and hideImmediately then
        exports.core_ui:uiPushEvent(Events.PUSH_RADIO_STATION_CHANGED, { station = false, loading = false })
        return
    end

    exports.core_ui:uiPushEvent(Events.PUSH_RADIO_STATION_CHANGED, { station = station or "off", loading = loading == true })

    hideCardTimer = setTimer(function()
        hideCardTimer = nil
        exports.core_ui:uiPushEvent(Events.PUSH_RADIO_STATION_CHANGED, { station = false, loading = false })
    end, HIDE_CARD_DELAY_MS, 1)
end

-- Attached to root, not resourceRoot - triggerClientEvent(occupant, ...)
-- fires the event ON THE PLAYER ELEMENT, which propagates up through
-- root (every element's ultimate ancestor), never through resourceRoot
-- (a separate node that only parents elements THIS resource created -
-- players aren't among them). A handler on resourceRoot here would never
-- have fired at all - this was the actual reason nothing happened.
addEvent(Events.RADIO_STATION_CHANGED, true)
addEventHandler(Events.RADIO_STATION_CHANGED, root, function(station)
    stopSound()

    if not station then
        pushCardState(nil, false)
        return
    end

    pushCardState(station, true)

    sound = playSound(station.url, true, false)
    if not sound then
        return
    end

    setSoundVolume(sound, VOLUME)

    -- onClientSoundStream fires once the stream actually starts playing
    -- (or fails) - playSound() itself returns immediately, well before
    -- the real audio data has buffered, so the loading state waits for
    -- this rather than assuming "returned an element" means "audible".
    -- Captured as thisSound (not the outer `sound`) - by the time this
    -- fires, a fast station change may have already replaced the module-
    -- level `sound` with a newer stream, and this stale handler must not
    -- push a loading update for a station that isn't current anymore.
    local thisSound = sound
    addEventHandler("onClientSoundStream", thisSound, function(success)
        if sound == thisSound and isElement(thisSound) then
            pushCardState(station, not success)
        end
    end)
end)

addEventHandler("onClientVehicleExit", root, function(player)
    if player == localPlayer then
        stopSound()
        pushCardState(nil, false, true)
    end
end)

-- Covers a vehicle disappearing out from under the local player without a
-- normal exit ever firing - onClientVehicleExit is NOT guaranteed here:
-- destroyElement() on an occupied vehicle (e.g. gm_vehicles/server/
-- VehicleStorageService.lua's own store-zone sweep destroying an
-- abandoned/rejected vehicle, or VehicleService.storeVehicle removing one
-- that got successfully stored) just removes the element outright, MTA
-- doesn't synthesize an exit event for the ped who was riding it. Without
-- this, the last station's stream (and its "now playing" card) would keep
-- playing/showing indefinitely for a vehicle that no longer exists.
-- Checked BEFORE the element is gone (getPedOccupiedVehicle still
-- resolves it in this handler), not source == localPlayer's own vehicle
-- data (already gone by the time any such lookup would run).
addEventHandler("onClientElementDestroy", root, function()
    if source == getPedOccupiedVehicle(localPlayer) then
        stopSound()
        pushCardState(nil, false, true)
    end
end)

addEvent(Events.RADIO_STATIONS_RECEIVED, true)
addEventHandler(Events.RADIO_STATIONS_RECEIVED, root, function(stations)
    exports.core_ui:uiPushEvent(Events.PUSH_RADIO_STATIONS, stations)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- "down", not "both" - mouse wheel binds are known to misbehave with
    -- "both" in MTA (the old version of this file used "down" too; this
    -- got changed to "both" without reason during the rewrite).
    bindKey("mouse_wheel_up", "down", scrollStation)
    bindKey("mouse_wheel_down", "down", scrollStation)
    bindKey("r", "down", function() requestChangeStation(false) end)

    -- Static/fixed list, requested once - the frontend needs it to show
    -- the upcoming station's name next to the skip glyphs (RadioCard.tsx),
    -- not just react to RADIO_STATION_CHANGED after the fact.
    triggerServerEvent(Events.RADIO_REQUEST_STATIONS, resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, stopSound)
