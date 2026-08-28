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
    totalSeconds = 0
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_DUTY_STARTED, data)
    startTicker()
end)

addEvent(Events.GROUP_DUTY_ENDED, true)
addEventHandler(Events.GROUP_DUTY_ENDED, root, function()
    stopTicker()
    exports.core_ui:uiPushEvent(Events.PUSH_GROUP_DUTY_ENDED, {})
end)

addEvent(Events.GROUP_DUTY_SYNC, true)
addEventHandler(Events.GROUP_DUTY_SYNC, root, function(data)
    if type(data) == "table" and type(data.totalSeconds) == "number" then
        totalSeconds = totalSeconds + data.totalSeconds
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopTicker()
end)
