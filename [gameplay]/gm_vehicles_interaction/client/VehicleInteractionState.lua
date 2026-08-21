-- Radial vehicle interaction menu: hold left Shift while driving to show
-- it, scroll to move the selection around the ring, space to activate
-- the selected option - never the mouse cursor (see this file's own
-- design note: matches this project's existing "no guiSetInputEnabled
-- fight" lesson from gm_scoreboard's own right-click saga, and scroll/
-- space are both already free while driving - Shift itself is normally
-- sprint, which does nothing while in a vehicle anyway).
--
-- Only engine/lights/lock/handbrake are real, server-authoritative
-- options today (see VehicleInteractionService.lua) - siren/horn/trunk
-- from the reference screenshot this was modeled on have no backing
-- system in this project and are pushed to the frontend as disabled
-- placeholders, not hidden entirely, so the ring's layout matches the
-- reference without pretending those features work.
--
-- A separate resource from gm_vehicles on purpose - see
-- VehicleInteractionService.lua's own module comment: this works on ANY
-- vehicle the local player is driving, not just gm_vehicles's own
-- persistent ones.
VehicleInteractionState = VehicleInteractionState or {}

local shiftHeld = false
local menuOpen = false

--- @return vehicle|nil the vehicle localPlayer is currently driving
local function drivenVehicle()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and getVehicleController(vehicle) == localPlayer then
        return vehicle
    end
    return nil
end

local function openMenu()
    if menuOpen then
        return
    end
    if not drivenVehicle() then
        return
    end
    menuOpen = true

    exports.core_ui:uiShowOverlay("vehicleInteraction")
    triggerServerEvent(Events.VEHICLE_INTERACTION_QUERY, resourceRoot)
end

local function closeMenu()
    if not menuOpen then
        return
    end
    menuOpen = false

    exports.core_ui:uiHideOverlay("vehicleInteraction")
end

--- @param action string one of "engine"/"lights"/"lock"/"handbrake"
local function requestToggle(action)
    if not menuOpen or not drivenVehicle() then
        return
    end
    triggerServerEvent(Events.VEHICLE_INTERACTION_TOGGLE, resourceRoot, action)
end

-- Scroll direction and the "activate" key are entirely a CEF-side concern
-- (which option is currently selected lives in BOTH BlackoutOverlay-style
-- Lua state AND the frontend - here, it's simplest to let the frontend
-- own "which option is highlighted" since that's pure presentation, and
-- only tell it to move the selection / activate the current one). Scroll
-- wheel and space are forwarded into the CEF overlay as plain push
-- events; VehicleMenuOverlay.tsx moves its own local selection and calls
-- back into Lua (via a dedicated client event) only when actually
-- activating an option, so this file never needs to track "which slice
-- is selected" itself.
addEventHandler("onClientKey", root, function(key, state)
    if key == "lshift" then
        if state then
            shiftHeld = true
            openMenu()
        else
            shiftHeld = false
            closeMenu()
        end
        return
    end

    if not menuOpen then
        return
    end

    if key == "mouse_wheel_up" then
        exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_INTERACTION_SCROLL, true)
    elseif key == "mouse_wheel_down" then
        exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_INTERACTION_SCROLL, false)
    elseif key == "space" then
        -- Space is GTA's own (rebindable, but commonly used) handbrake
        -- key - without canceling this, activating a menu option while
        -- driving would also yank the handbrake every time. onClientKey
        -- can only cancel a bind on the DOWN press, not the up/release
        -- (per MTA's own docs), which is fine here: `state == false`
        -- never activates anything anyway (see the `state` check below).
        cancelEvent()
        if state then
            exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_INTERACTION_ACTIVATE, true)
        end
    end
end)

--- The frontend confirms which action it activated (its own current
--- selection) via this (relayed through core_ui's ui:notify channel - see
--- Transport.lua's module comment - so `action` arrives already
--- JSON-decoded back into a real string) - see VehicleMenuOverlay.tsx's onActivate.
addEvent(Events.VEHICLE_INTERACTION_ACTIVATED, true)
addEventHandler(Events.VEHICLE_INTERACTION_ACTIVATED, root, function(action)
    requestToggle(action)
end)

addEvent(Events.PUSH_VEHICLE_INTERACTION_STATE, true)
addEventHandler(Events.PUSH_VEHICLE_INTERACTION_STATE, root, function(action, state)
    if source ~= localPlayer then
        return
    end
    exports.core_ui:uiPushEvent(Events.PUSH_VEHICLE_INTERACTION_STATE, { action = action or false, state = state })
end)

-- Driver leaving the vehicle (or the vehicle itself going away) closes
-- the menu even if Shift is still physically held - there's nothing left
-- to interact with.
addEventHandler("onClientVehicleExit", root, function(player)
    if player == localPlayer then
        closeMenu()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if menuOpen then
        closeMenu()
    end
end)

-- Exported so other client resources that also bind mouse_wheel_up/down
-- while driving (gm_radio's own scroll-to-change-station) can check this
-- before acting, and skip their own scroll handling while this menu is
-- open - otherwise scrolling to move the ring selection also changes the
-- radio station underneath it. See gm_radio/client/RadioState.lua's own
-- requestChangeStation.
function vehicleInteractionIsMenuOpen()
    return menuOpen
end
