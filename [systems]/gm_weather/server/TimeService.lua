local SYNC_INTERVAL_MS = 60 * 1000

local function syncTime()
    local real = getRealTime()
    setTime(real.hour, real.minute)
end

addEventHandler("onResourceStart", resourceRoot, function()
    syncTime()
    setMinuteDuration(60000)

    setTimer(syncTime, SYNC_INTERVAL_MS, 0)
end)
