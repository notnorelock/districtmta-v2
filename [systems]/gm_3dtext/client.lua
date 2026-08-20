-- Renders floating 3dtext elements and vehicle nametag text (vehicle:text)
-- above their world position. Candidate lists are rebuilt on a timer
-- (Text3D.REFRESH_INTERVAL) rather than every frame - only the draw
-- itself (screen projection, fade, LOS) needs per-frame freshness.

Text3D = Text3D or {}

Text3D.FADE_DISTANCE = 0.6
Text3D.MAX_DRAW_DISTANCE = 30
Text3D.REFRESH_INTERVAL = 250

-- Line-of-sight raycasts are one of the more expensive MTA calls - doing
-- one per visible text per frame (60/s) is wasteful when a text's
-- occlusion state realistically only needs to catch up a few times a
-- second. Cached per element, refreshed on this cadence instead.
Text3D.LOS_REFRESH_INTERVAL = 100

local mathMin = math.min
local mathMax = math.max

local visibleTexts = {}
local visibleVehicles = {}
local losCache = setmetatable({}, { __mode = "k" })

local DISCONNECT_REASON = {
    ["Unknown"] = "Nieznany",
    ["Quit"] = "Rozłączenie",
    ["Kicked"] = "Wyrzucony",
    ["Banned"] = "Ban",
    ["Bad Connection"] = "Problem z połączeniem",
    ["Timed out"] = "Crash",
}

local function dxDrawBorderedText(text, left, top, right, bottom, r, g, b, a, scale, font, alignX, alignY, clip, wordBreak, postGUI)
    dxDrawText(text:gsub("#%x%x%x%x%x%x", ""), left + 1, top + 1, right + 1, bottom + 1, tocolor(0, 0, 0, a), scale, font, alignX, alignY, clip, wordBreak, postGUI, true)
    dxDrawText(text, left, top, right, bottom, tocolor(r, g, b, a), scale, font, alignX, alignY, clip, wordBreak, postGUI, true)
end

--- Shared alpha falloff used by both 3dtext elements and vehicle text.
-- @param dist number
-- @param fadeDistance number
-- @return number 0-255
local function fadeAlpha(dist, fadeDistance)
    return mathMin(mathMax(0, (255 * ((fadeDistance - dist) / fadeDistance)) + 200), 255)
end

--- @param element userdata
-- @return boolean true if element shares localPlayer's interior+dimension
local function sameZone(element)
    return getElementDimension(localPlayer) == getElementDimension(element)
        and getElementInterior(localPlayer) == getElementInterior(element)
end

--- Cached isLineOfSightClear, refreshed at most every Text3D.LOS_REFRESH_INTERVAL ms per element.
-- @param element userdata cache key
-- @return boolean
local function isSightClear(element, cx, cy, cz, x, y, z, checkVehicles)
    local cached = losCache[element]
    local tick = getTickCount()
    if cached and tick - cached.tick < Text3D.LOS_REFRESH_INTERVAL then
        return cached.clear
    end

    local clear = isLineOfSightClear(cx, cy, cz, x, y, z, true, checkVehicles, false, true, true, true) == true
    losCache[element] = { clear = clear, tick = tick }
    return clear
end

--- Renders one floating text at a world position: distance check, cached
--- LOS occlusion, screen projection, distance-fade, then the actual draw.
-- @param element userdata cache/identity key (3dtext element or vehicle)
-- @param checkSight boolean whether to occlusion-test against isLineOfSightClear
-- @param checkVehicles boolean passed through as the LOS check's vehicle-occlusion flag
local function drawWorldText(element, x, y, z, text, drawDistance, scale, cx, cy, cz, checkSight, checkVehicles)
    local dist = getDistanceBetweenPoints3D(x, y, z, cx, cy, cz)
    if dist >= drawDistance then
        return
    end

    if checkSight and not isSightClear(element, cx, cy, cz, x, y, z, checkVehicles) then
        return
    end

    local sx, sy = getScreenFromWorldPosition(x, y, z, 0.2)
    if not sx or not sy then
        return
    end

    local fadeDistance = drawDistance * Text3D.FADE_DISTANCE
    local alpha = fadeAlpha(dist, fadeDistance)
    if alpha <= 0 then
        return
    end

    dxDrawBorderedText(text, sx, sy, sx, sy, 230, 230, 230, alpha,
        scale * ((drawDistance - dist) / drawDistance), "default-bold", "center", "center", false, false, false)
end

--- Rebuilds the visibleTexts/visibleVehicles candidate lists - called on
--- Text3D.REFRESH_INTERVAL, not every frame.
Text3D.refreshCandidates = function()
    local cx, cy, cz = getCameraMatrix()

    local nextTexts = {}
    for _, element in ipairs(getElementsByType("3dtext", root, true)) do
        if sameZone(element) then
            local x, y, z = getElementPosition(element)
            local drawDistance = getElementData(element, "range") or Text3D.MAX_DRAW_DISTANCE
            if getDistanceBetweenPoints3D(x, y, z, cx, cy, cz) < drawDistance then
                nextTexts[#nextTexts + 1] = element
            end
        end
    end
    visibleTexts = nextTexts

    local nextVehicles = {}
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(vehicle, "vehicle:text") and sameZone(vehicle) then
            local x, y, z = getElementPosition(vehicle)
            local drawDistance = getElementData(vehicle, "vehicle:textRange") or Text3D.MAX_DRAW_DISTANCE
            if getDistanceBetweenPoints3D(x, y, z, cx, cy, cz) < drawDistance then
                nextVehicles[#nextVehicles + 1] = vehicle
            end
        end
    end
    visibleVehicles = nextVehicles
end

--- Draws every candidate 3dtext for the current frame.
Text3D.renderTexts = function(cx, cy, cz)
    for _, element in ipairs(visibleTexts) do
        if isElement(element) and sameZone(element) then
            local attachedTo = getElementData(element, "attach")
            local x, y, z
            if attachedTo and isElement(attachedTo) then
                x, y, z = getElementPosition(attachedTo)
                setElementPosition(element, x, y, z)
            else
                x, y, z = getElementPosition(element)
            end

            local drawDistance = getElementData(element, "range") or Text3D.MAX_DRAW_DISTANCE
            local text = getElementData(element, "text") or ""
            local scale = getElementData(element, "scale") or 1
            local checkSight = not getElementData(element, "sightCheckDisabled")

            drawWorldText(element, x, y, z, text, drawDistance, scale, cx, cy, cz, checkSight, true)
        end
    end
end

--- Draws every candidate vehicle's vehicle:text for the current frame.
Text3D.renderVehicleTexts = function(cx, cy, cz)
    for _, vehicle in ipairs(visibleVehicles) do
        if isElement(vehicle) and sameZone(vehicle) then
            local text = getElementData(vehicle, "vehicle:text")
            if text then
                local x, y, z = getElementPosition(vehicle)
                local drawDistance = getElementData(vehicle, "vehicle:textRange") or Text3D.MAX_DRAW_DISTANCE
                local scale = getElementData(vehicle, "vehicle:textScale") or 0.8

                drawWorldText(vehicle, x, y, z, tostring(text), drawDistance, scale, cx, cy, cz, true, false)
            end
        end
    end
end

--- Spawns a temporary "<player> wyszedł(a) z gry (<reason>)" 3dtext at
--- the quitting player's last position, auto-destroyed after 10s.
-- @param player userdata
-- @param reason string raw MTA quit reason
Text3D.announceQuit = function(player, reason)
    local x, y, z = getElementPosition(player)

    local text = createElement("3dtext")
    setElementPosition(text, x, y, z)
    setElementInterior(text, 0)
    setElementDimension(text, 0)
    setElementData(text, "text", string.format("%s wyszedł(a) z gry (%s)", getPlayerName(player), DISCONNECT_REASON[reason] or reason), false)
    setElementData(text, "scale", 1)
    setTimer(destroyElement, 10 * 1000, 1, text)
end

setTimer(Text3D.refreshCandidates, Text3D.REFRESH_INTERVAL, 0)

addEventHandler("onClientPreRender", root, function()
    local cx, cy, cz = getCameraMatrix()
    Text3D.renderTexts(cx, cy, cz)
    Text3D.renderVehicleTexts(cx, cy, cz)
end, true, "high+10")

addEventHandler("onClientPlayerQuit", root, function(reason)
    Text3D.announceQuit(source, reason)
end)
