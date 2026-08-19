-- Client-side blackout presentation: locks out controls, hides the normal
-- HUD, and pushes a countdown into the CEF overlay (see BlackoutOverlay.tsx
-- on the frontend - rendered inside CEF, not dxDraw, same reasoning as
-- gm_voice/gm_radio's HUD elements). The server (BlackoutService.lua) is
-- fully authoritative over WHEN blackout starts/ends and what health the
-- player is left with - this file only reflects that state locally.
BlackoutState = BlackoutState or {}

local active = false
local tickTimer = nil
-- Local getTickCount() reference point for the countdown, NOT the
-- player's system clock - getRealTime()'s client-side timestamp is
-- explicitly documented as "time as set on client's computer", which
-- could be wrong/in a different timezone than the server's os.time() the
-- BLACKOUT_UNTIL end time was computed from. getTickCount() is a
-- monotonic counter with no such dependency, so the countdown here always
-- agrees with the server's own clock once seeded, regardless of what the
-- player's clock says - seeding it (setReference below) is the one place
-- that has to fall back to comparing clocks at all, and only once, not
-- on every tick.
local referenceTick = 0
local referenceSecondsRemaining = 0

--- Seeds the getTickCount() reference point used by secondsRemaining()
--- below. Called with a value the server just computed (BLACKOUT_STARTED's
--- argument, always fresh and exact) or, on a resource restart with no
--- fresh push available, a one-time clock-based estimate from
--- ElementData.Player.BLACKOUT_UNTIL - see the onClientResourceStart
--- handler at the bottom of this file.
-- @param seconds number
local function setReference(seconds)
    referenceTick = getTickCount()
    referenceSecondsRemaining = seconds
end

--- @return number|nil seconds remaining - nil if not currently blacked out.
local function secondsRemaining()
    if type(getElementData(localPlayer, ElementData.Player.BLACKOUT_UNTIL)) ~= "number" then
        return nil
    end
    local elapsedS = (getTickCount() - referenceTick) / 1000
    return math.max(0, math.ceil(referenceSecondsRemaining - elapsedS))
end

--- Pushes the current countdown into the CEF overlay. secondsRemaining
--- nil hides the overlay entirely (see BlackoutOverlay.tsx). canSelfRevive
--- mirrors whether E currently does anything - true once the countdown
--- reaches zero, same condition requestSelfRevive below gates on.
local function pushState()
    local remaining = secondsRemaining()
    exports.core_ui:uiPushEvent(Events.PUSH_BLACKOUT_UPDATED, {
        secondsRemaining = remaining or false,
        canSelfRevive = remaining ~= nil and remaining <= 0,
    })
end

--- Requests the server end blackout early - only actually does anything
--- once the local countdown has reached zero; the server independently
--- re-checks this itself (see BlackoutService.lua) rather than trusting
--- this client-side gate, which only exists to avoid firing a request
--- that can never succeed while the countdown is still running.
local function requestSelfRevive()
    if not active or (secondsRemaining() or 1) > 0 then
        return
    end
    triggerServerEvent(Events.BLACKOUT_SELF_REVIVE, resourceRoot)
end

--- @param seconds number initial countdown value, from BLACKOUT_STARTED
--        or a resource-restart clock estimate - see setReference above.
local function startLocal(seconds)
    setReference(seconds)

    if active then
        return
    end
    active = true

    exports.core_ui:uiShowOverlay("blackout")
    exports.core_ui:uiHideOverlay("hud")
    toggleAllControls(false)
    -- "e" (the raw key name), not the "enter_exit" GTA control name - a
    -- plain bindKey on a key name (as opposed to a control name) keeps
    -- working even after toggleAllControls(false) above disables GTA/MTA
    -- controls, which is exactly why this is bound this way rather than
    -- via bindControlKeys or relying on the (disabled) enter_exit control.
    bindKey("e", "down", requestSelfRevive)

    pushState()
    tickTimer = setTimer(pushState, 1000, 0)
end

local function endLocal()
    if not active then
        return
    end
    active = false

    if isTimer(tickTimer) then
        killTimer(tickTimer)
    end
    tickTimer = nil

    exports.core_ui:uiHideOverlay("blackout")
    exports.core_ui:uiShowOverlay("hud")
    toggleAllControls(true)
    unbindKey("e", "down", requestSelfRevive)

    exports.core_ui:uiPushEvent(Events.PUSH_BLACKOUT_UPDATED, { secondsRemaining = false, canSelfRevive = false })
end

addEvent(Events.BLACKOUT_STARTED, true)
addEventHandler(Events.BLACKOUT_STARTED, root, function(secondsTotal)
    if source ~= localPlayer then
        return
    end
    startLocal(secondsTotal)
end)

addEvent(Events.BLACKOUT_ENDED, true)
addEventHandler(Events.BLACKOUT_ENDED, root, function()
    if source ~= localPlayer then
        return
    end
    endLocal()
end)

-- A resource restart mid-blackout (gm_blackout itself, or core_ui/ui_hud
-- recreating the CEF browser) resets this file's own `active` flag and
-- the browser's overlay state, but ElementData.Player.BLACKOUT_UNTIL
-- survives on the player element - re-derive local state from it instead
-- of waiting for a BLACKOUT_STARTED push that may never come again this
-- session. This is the one place a client clock read is unavoidable (no
-- fresh server-computed value is available here), but it only seeds the
-- getTickCount() reference once - every subsequent tick still counts down
-- purely off getTickCount(), so a wrong client clock only ever causes a
-- one-time few-second skew at most, never a growing drift.
addEventHandler("onClientResourceStart", resourceRoot, function()
    local until_ = getElementData(localPlayer, ElementData.Player.BLACKOUT_UNTIL)
    if type(until_) == "number" then
        startLocal(math.max(0, until_ - getRealTime().timestamp))
    end
end)
