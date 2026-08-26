local REGION_CHECK_INTERVAL_MS = 250

local lastRegionId = nil
local lastCheckTick = 0

local function checkRegion()
    if not exports.core_shared:canPlayerInteract(nil, { requiresSpawned = true, inVehicle = false, whileBlackout = true }) then
        return
    end

    local x, y, z = getElementPosition(localPlayer)
    if getElementInterior(localPlayer) ~= 0 or getElementDimension(localPlayer) ~= 0 then
        return
    end

    local cityName = getZoneName(x, y, z, true)
    if cityName == lastRegionId then
        return
    end
    lastRegionId = cityName

    triggerServerEvent(Events.WEATHER_REQUEST_CURRENT, resourceRoot)
end

addEvent(Events.WEATHER_CURRENT_RECEIVED, true)
addEventHandler(Events.WEATHER_CURRENT_RECEIVED, root, function(data)
    setWeatherBlended(data.weatherId)
    exports.core_ui:uiPushEvent(Events.PUSH_WEATHER_CURRENT, data)
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    lastRegionId = nil
    lastCheckTick = 0
end)

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    if now - lastCheckTick < REGION_CHECK_INTERVAL_MS then
        return
    end
    lastCheckTick = now

    checkRegion()
end)
