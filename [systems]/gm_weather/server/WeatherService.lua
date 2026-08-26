WeatherService = WeatherService or {}

local REROLL_INTERVAL_MS = 60 * 60 * 1000

local currentWeather = {}

local function rollWeather(region)
    local totalChance = 0
    for _, entry in ipairs(region.pool) do
        totalChance = totalChance + entry.chance
    end

    local roll = math.random(1, totalChance)
    local accumulated = 0

    for _, entry in ipairs(region.pool) do
        accumulated = accumulated + entry.chance
        if roll <= accumulated then
            local weatherId = entry.weathers[math.random(1, #entry.weathers)]
            return { weatherId = weatherId, icon = entry.icon, labelKey = entry.labelKey }
        end
    end

    local first = region.pool[1]
    return { weatherId = first.weathers[1], icon = first.icon, labelKey = first.labelKey }
end

function WeatherService.getRegionWeather(regionId, region, cityName)
    local weather = currentWeather[regionId]
    if not weather then
        weather = rollWeather(region)
        currentWeather[regionId] = weather
    end

    return {
        region = regionId,
        city = cityName,
        weatherId = weather.weatherId,
        icon = weather.icon,
        labelKey = weather.labelKey,
    }
end

local function rerollAllRegions()
    for _, region in ipairs(WeatherRegions.REGIONS) do
        if currentWeather[region.id] then
            currentWeather[region.id] = rollWeather(region)

            for _, targetPlayer in ipairs(getElementsByType("player")) do
                if getElementData(targetPlayer, ElementData.Player.SPAWNED) == true then
                    local x, y, z = getElementPosition(targetPlayer)
                    local playerRegion, cityName = WeatherRegions.regionAt(x, y, z)
                    if playerRegion and playerRegion.id == region.id then
                        triggerClientEvent(targetPlayer, Events.WEATHER_CURRENT_RECEIVED, targetPlayer, WeatherService.getRegionWeather(region.id, region, cityName))
                    end
                end
            end
        end
    end
end

addEvent(Events.WEATHER_REQUEST_CURRENT, true)
addEventHandler(Events.WEATHER_REQUEST_CURRENT, root, function()
    local player = client
    local x, y, z = getElementPosition(player)
    local region, cityName = WeatherRegions.regionAt(x, y, z)
    if not region then
        return
    end

    triggerClientEvent(player, Events.WEATHER_CURRENT_RECEIVED, player, WeatherService.getRegionWeather(region.id, region, cityName))
end)

setTimer(rerollAllRegions, REROLL_INTERVAL_MS, 0)
