-- Forwards GroupDutyService.lua's duty start/end/sync pushes into CEF for
-- DutyIndicator.tsx - always-mounted, driven purely by store state (no
-- overlay show/hide here, unlike GroupPanelState.lua's own panel toggle).
-- Also runs a local 1-second ticker between server syncs so the HUD's
-- elapsed time counts up smoothly instead of jumping every
-- DUTY_TICK_INTERVAL_MS (10s) - self-corrects on every server push, so a
-- lost/delayed sync is never more than one tick's worth of drift.
GroupDutyState = GroupDutyState or {}

local tickTimer = nil
local totalSeconds = 0

local function startTicker()
    if isTimer(tickTimer) then
        return
    end
    tickTimer = setTimer(function()
        totalSeconds = totalSeconds + 1
        exports.core_ui:uiPushEvent(Events.PUSH_GROUP_DUTY_SYNC, { totalSeconds = totalSeconds })
    end, 1000, 0)
end

local function stopTicker()
    if isTimer(tickTimer) then
        killTimer(tickTimer)
    end
    tickTimer = nil
end

addEvent(Events.GROUP_DUTY_STARTED, true)
addEventHandler(Events.GROUP_DUTY_STARTED, root, function(data)
    totalSeconds = type(data) == "table" and (data.totalSeconds or 0) or 0
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_DUTY_STARTED, data)
    startTicker()
end)

addEvent(Events.GROUP_DUTY_ENDED, true)
addEventHandler(Events.GROUP_DUTY_ENDED, root, function()
    stopTicker()
    -- uiPushEvent always needs a real value for its data argument -
    -- BrowserManager.lua's UI.pushEvent runs it through toJSON, which
    -- errors on a bare nil - see PUSH_GROUP_DUTY_STARTED/_SYNC's own
    -- table payloads above, this one just has nothing to say.
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_DUTY_ENDED, {})
end)

addEvent(Events.GROUP_DUTY_SYNC, true)
addEventHandler(Events.GROUP_DUTY_SYNC, root, function(data)
    -- data.totalSeconds from the server is only the amount flushed THIS
    -- tick (see GroupDutyService.lua's runDutyTick), not a running total -
    -- fold it into our own local counter rather than overwriting it.
    if type(data) == "table" and type(data.totalSeconds) == "number" then
        totalSeconds = totalSeconds + data.totalSeconds
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopTicker()
end)
