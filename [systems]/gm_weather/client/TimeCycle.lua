local INTERPOLATION_LENGTH_HOURS = 1
local HOUR_BOUNDARIES = { 0, 5, 6, 7, 12, 19, 20, 22, 24 }
local NUM_HOUR_SLOTS = 8

local Timecyc = {} -- forget i removed it bruh and i made it brok

Weather = {
    interpolateStart = 0,
    old = getWeather(),
    new = getWeather(),
    interpolation = 1,
    data = {},
}

local T = {
    ambR = 1, ambG = 2, ambB = 3,
    ambR_obj = 4, ambG_obj = 5, ambB_obj = 6,
    dirR = 7, dirG = 8, dirB = 9,
    skyTopR = 10, skyTopG = 11, skyTopB = 12,
    skyBotR = 13, skyBotG = 14, skyBotB = 15,
    sunCoreR = 16, sunCoreG = 17, sunCoreB = 18,
    sunCoronaR = 19, sunCoronaG = 20, sunCoronaB = 21,
    sunSz = 22, sprSz = 23, sprBght = 24,
    shad = 25, lightShad = 26, poleShad = 27,
    farClp = 28, fogSt = 29, lightGnd = 30,
    cloudR = 31, cloudG = 32, cloudB = 33,
    fluffyBotR = 34, fluffyBotG = 35, fluffyBotB = 36,
    waterR = 37, waterG = 38, waterB = 39, waterA = 40,
    postfx1A = 41, postfx1R = 42, postfx1G = 43, postfx1B = 44,
    postfx2A = 45, postfx2R = 46, postfx2G = 47, postfx2B = 48,
    cloudAlpha = 49, radiosityLimit = 50, waterFogAlpha = 51, dirMult = 52,
}

function loadTimeCycle(filename)
    local file = fileOpen(filename)
    if not file then
        return
    end

    local contents = fileRead(file, fileGetSize(file))
    local lines = split(contents:gsub("\r", ""), "\n")
    fileClose(file)

    local weatherId = 0
    for i = 1, #lines do
        if string.find(lines[i], "////////////") then
            weatherId = weatherId + 1
        end

        if lines[i]:sub(1, 1) ~= "/" and lines[i]:sub(2, 1) ~= "/" then
            local columns = split(lines[i]:gsub("\t", " "), " ")
            if Timecyc[weatherId] == nil then
                Timecyc[weatherId] = {}
            end
            table.insert(Timecyc[weatherId], columns)
        end
    end
end

local function interpolateValue(a, b, fa, fb)
    return fa * a + fb * b
end

local function interpolateRGB(a, b, fa, fb)
    return { fa * a[1] + fb * b[1], fa * a[2] + fb * b[2], fa * a[3] + fb * b[3] }
end

local function interpolateRGBA(a, b, fa, fb)
    return { fa * a[1] + fb * b[1], fa * a[2] + fb * b[2], fa * a[3] + fb * b[3], fa * a[4] + fb * b[4] }
end

local function interpolate(a, b, fa, fb, isCurrent)
    local weather = {}

    if not isCurrent then
        weather.amb = interpolateRGB({ a[T.ambR], a[T.ambG], a[T.ambB] }, { b[T.ambR], b[T.ambG], b[T.ambB] }, fa, fb)
        weather.amb_obj = interpolateRGB({ a[T.ambR_obj], a[T.ambG_obj], a[T.ambB_obj] }, { b[T.ambR_obj], b[T.ambG_obj], b[T.ambB_obj] }, fa, fb)
        weather.sky_top = interpolateRGB({ a[T.skyTopR], a[T.skyTopG], a[T.skyTopB] }, { b[T.skyTopR], b[T.skyTopG], b[T.skyTopB] }, fa, fb)
        weather.sky_bot = interpolateRGB({ a[T.skyBotR], a[T.skyBotG], a[T.skyBotB] }, { b[T.skyBotR], b[T.skyBotG], b[T.skyBotB] }, fa, fb)
        weather.sun_core = interpolateRGB({ a[T.sunCoreR], a[T.sunCoreG], a[T.sunCoreB] }, { b[T.sunCoreR], b[T.sunCoreG], b[T.sunCoreB] }, fa, fb)
        weather.sun_corona = interpolateRGB({ a[T.sunCoronaR], a[T.sunCoronaG], a[T.sunCoronaB] }, { b[T.sunCoronaR], b[T.sunCoronaG], b[T.sunCoronaB] }, fa, fb)
        weather.sun_size = interpolateValue(a[T.sunSz], b[T.sunSz], fa, fb)
        weather.postfx1 = interpolateRGBA({ a[T.postfx1R], a[T.postfx1G], a[T.postfx1B], a[T.postfx1A] }, { b[T.postfx1R], b[T.postfx1G], b[T.postfx1B], b[T.postfx1A] }, fa, fb)
        weather.postfx2 = interpolateRGBA({ a[T.postfx2R], a[T.postfx2G], a[T.postfx2B], a[T.postfx2A] }, { b[T.postfx2R], b[T.postfx2G], b[T.postfx2B], b[T.postfx2A] }, fa, fb)
        weather.dirMult = interpolateValue(a[T.dirMult], b[T.dirMult], fa, fb)
        weather.fogSt = interpolateValue(a[T.fogSt], b[T.fogSt], fa, fb)
        weather.farClp = interpolateValue(a[T.farClp], b[T.farClp], fa, fb)
        weather.radiosityLimit = interpolateValue(a[T.radiosityLimit], b[T.radiosityLimit], fa, fb)
    else
        weather.amb = interpolateRGB(a.amb, b.amb, fa, fb)
        weather.amb_obj = interpolateRGB(a.amb_obj, b.amb_obj, fa, fb)
        weather.sky_top = interpolateRGB(a.sky_top, b.sky_top, fa, fb)
        weather.sky_bot = interpolateRGB(a.sky_bot, b.sky_bot, fa, fb)
        weather.sun_core = interpolateRGB(a.sun_core, b.sun_core, fa, fb)
        weather.sun_corona = interpolateRGB(a.sun_corona, b.sun_corona, fa, fb)
        weather.sun_size = interpolateValue(a.sun_size, b.sun_size, fa, fb)
        weather.postfx1 = interpolateRGBA(a.postfx1, b.postfx1, fa, fb)
        weather.postfx2 = interpolateRGBA(a.postfx2, b.postfx2, fa, fb)
        weather.dirMult = interpolateValue(a.dirMult, b.dirMult, fa, fb)
        weather.fogSt = interpolateValue(a.fogSt, b.fogSt, fa, fb)
        weather.farClp = interpolateValue(a.farClp, b.farClp, fa, fb)
        weather.radiosityLimit = interpolateValue(a.radiosityLimit, b.radiosityLimit, fa, fb)
    end

    return weather
end

local function getColourSet(hourSlot, weatherId)
    hourSlot = hourSlot == 8 and 1 or hourSlot
    return Timecyc[weatherId][hourSlot]
end

function updateSA(weatherId, currentHour, currentMinute)
    Weather.old = weatherId

    local time = currentHour + currentMinute / 60.0

    local curHourSel = 1
    while time >= HOUR_BOUNDARIES[curHourSel + 1] do
        curHourSel = curHourSel + 1
    end
    curHourSel = curHourSel == 0 and 1 or curHourSel

    local nextHourSel = (curHourSel + 1) % NUM_HOUR_SLOTS
    nextHourSel = nextHourSel == 0 and 1 or nextHourSel

    local curHour = HOUR_BOUNDARIES[curHourSel]
    local nextHour = HOUR_BOUNDARIES[curHourSel + 1]
    local timeInterp = (time - curHour) / (nextHour - curHour)

    local curOld = getColourSet(curHourSel, Weather.old + 1)
    local curNew = getColourSet(curHourSel, Weather.new + 1)
    local nextOld = getColourSet(nextHourSel, Weather.old + 1)
    local nextNew = getColourSet(nextHourSel, Weather.new + 1)

    local oldInterp = interpolate(curOld, nextOld, 1.0 - timeInterp, timeInterp)
    local newInterp = interpolate(curNew, nextNew, 1.0 - timeInterp, timeInterp)
    local currentColours = interpolate(oldInterp, newInterp, 1.0 - Weather.interpolation, Weather.interpolation, true)

    setSkyGradient(currentColours.sky_top[1], currentColours.sky_top[2], currentColours.sky_top[3], currentColours.sky_bot[1], currentColours.sky_bot[2], currentColours.sky_bot[3])
    setSunColor(currentColours.sun_core[1], currentColours.sun_core[2], currentColours.sun_core[3], currentColours.sun_corona[1], currentColours.sun_corona[2], currentColours.sun_corona[3])
    setSunSize(currentColours.sun_size)
    setFogDistance(currentColours.fogSt)
    setFarClipDistance(currentColours.farClp)
    Weather.data = currentColours

    if Weather.interpolateStart ~= 0 then
        if Weather.interpolation < 1 then
            local endTime = INTERPOLATION_LENGTH_HOURS * 60000
            Weather.interpolation = (getTickCount() - Weather.interpolateStart) / endTime
        else
            Weather.old = Weather.new
            setWeather(Weather.new)
            Weather.interpolateStart = 0
        end
    end
end

local function renderTimecycLoop()
    local hour, minute = getTime()
    updateSA(getWeather(), hour, minute)
end

function setWeatherBlended(weatherId)
    Weather.new = weatherId
    Weather.interpolateStart = getTickCount()
    Weather.interpolation = 0
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadTimeCycle("client/timecyc.dat")
    addEventHandler("onClientRender", root, renderTimecycLoop, false, "low")
end)
