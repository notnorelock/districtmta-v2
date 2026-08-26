local RANGE = 10
local SCROLL_DELAY_MS = 90
local SCAN_INTERVAL_MS = 150
local OUTLINE_RAY_RADIUS = 2.2
local MAX_TARGET_RAY_RADIUS = 1.2
local LOS_CHECK_MIN_DISTANCE = 6
local OUTLINE_RANGE_HYSTERESIS = 1.5
local OUTLINE_RAY_RADIUS_HYSTERESIS = 0.8

local activeTarget = nil
local lastScrollTick = 0
local outlinedElements = {}
local lastListRequestTarget = nil
local lookingForInteractions = false

local function nearbyElements()
    local list = {}
    for _, player in ipairs(getElementsByType("player")) do
        if player ~= localPlayer then
            list[#list + 1] = player
        end
    end
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if vehicle ~= getPedOccupiedVehicle(localPlayer) then
            list[#list + 1] = vehicle
        end
    end
    for _, object in ipairs(getElementsByType("object")) do
        list[#list + 1] = object
    end
    return list
end

local function sameZone(element)
    return getElementDimension(localPlayer) == getElementDimension(element)
        and getElementInterior(localPlayer) == getElementInterior(element)
end

local function cameraLookRay()
    local cx, cy, cz, lx, ly, lz = getCameraMatrix()
    local dx, dy, dz = lx - cx, ly - cy, lz - cz
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len <= 0.001 then
        return cx, cy, cz, 0, 1, 0
    end
    return cx, cy, cz, dx / len, dy / len, dz / len
end

local function perpDistanceFromRay(cx, cy, cz, dx, dy, dz, x, y, z)
    local px, py, pz = x - cx, y - cy, z - cz
    local t = px * dx + py * dy + pz * dz
    if t < 0 then
        return nil
    end

    local closestX, closestY, closestZ = cx + dx * t, cy + dy * t, cz + dz * t
    return getDistanceBetweenPoints3D(x, y, z, closestX, closestY, closestZ)
end

local function rangeFilteredCandidates()
    local px, py, pz = getElementPosition(localPlayer)
    local cx, cy, cz, dx, dy, dz = cameraLookRay()
    local list = {}
    local nextOutlined = {}

    for _, element in ipairs(nearbyElements()) do
        if sameZone(element) then
            local x, y, z = getElementPosition(element)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local rayDist = perpDistanceFromRay(cx, cy, cz, dx, dy, dz, x, y, z)

            local rangeLimit, rayLimit = RANGE, OUTLINE_RAY_RADIUS
            if outlinedElements[element] then
                rangeLimit = RANGE + OUTLINE_RANGE_HYSTERESIS
                rayLimit = OUTLINE_RAY_RADIUS + OUTLINE_RAY_RADIUS_HYSTERESIS
            end

            if dist <= rangeLimit and rayDist ~= nil and rayDist <= rayLimit then
                list[#list + 1] = element
                nextOutlined[element] = true
            end
        end
    end

    outlinedElements = nextOutlined
    return list
end

local function closestToLookRay(candidates)
    local px, py, pz = getElementPosition(localPlayer)
    local cx, cy, cz, dx, dy, dz = cameraLookRay()

    local best, bestRayDist = nil, MAX_TARGET_RAY_RADIUS

    for _, element in ipairs(candidates) do
        local x, y, z = getElementPosition(element)
        local rayDist = perpDistanceFromRay(cx, cy, cz, dx, dy, dz, x, y, z)

        if rayDist ~= nil and rayDist < bestRayDist then
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local sightClear = dist <= LOS_CHECK_MIN_DISTANCE
                or isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, true, true, true)

            if sightClear then
                best, bestRayDist = element, rayDist
            end
        end
    end

    return best
end

local function requestListFor(element)
    if element == lastListRequestTarget then
        return
    end
    lastListRequestTarget = element

    if not element then
        exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_LIST, {})
        return
    end

    triggerServerEvent(Events.INTERACTION_REQUEST_LIST, resourceRoot, element)
end

local function refreshCandidates()
    if not lookingForInteractions then
        return
    end

    local candidates = rangeFilteredCandidates()
    toggleWallShader(true, candidates)

    local target = closestToLookRay(candidates)
    if target ~= activeTarget then
        activeTarget = target
        requestListFor(target)

        if not target then
            exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_TARGET, false)
        end
    end
end

local function openInteractionMode()
    if lookingForInteractions then
        return
    end

    lookingForInteractions = true
    activeTarget = nil
    lastListRequestTarget = nil

    exports.core_ui:uiShowOverlay("worldInteraction")
    refreshCandidates()
end

local function closeInteractionMode()
    if not lookingForInteractions then
        return
    end
    lookingForInteractions = false

    toggleWallShader(false, {})
    activeTarget = nil
    lastListRequestTarget = nil
    outlinedElements = {}

    exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_LIST, {})
    exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_TARGET, false)

    exports.core_ui:uiHideOverlay("worldInteraction")
end

function isLookingForInteraction()
    return isLookingForInteractions
end

local toggleConditions = {
    withChatbox = false,
    requiresSpawned = true,
    whileOpenInventory = false,
    whileBlackout = false,
    inVehicle = true
}
local function toggleInteractionMode()
    if not exports.core_shared:canPlayerInteract(nil, toggleConditions) then
        return
    end

    if lookingForInteractions then
        closeInteractionMode()
    else
        openInteractionMode()
    end
end

addEventHandler("onClientKey", root, function(key, state)
    if key == "e" then
        if state then
            toggleInteractionMode()
        end
        return
    end

    if not lookingForInteractions then
        return
    end

    if key == "mouse_wheel_up" then
        cancelEvent()
        if activeTarget and getTickCount() >= lastScrollTick + SCROLL_DELAY_MS then
            lastScrollTick = getTickCount()
            exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_NAVIGATE, -1)
        end
    elseif key == "mouse_wheel_down" then
        cancelEvent()
        if activeTarget and getTickCount() >= lastScrollTick + SCROLL_DELAY_MS then
            lastScrollTick = getTickCount()
            exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_NAVIGATE, 1)
        end
    elseif key == "space" then
        cancelEvent()
        if state and activeTarget then
            exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_ACTIVATE, true)
        end
    end
end)

setTimer(refreshCandidates, SCAN_INTERVAL_MS, 0)

addEventHandler("onClientRender", root, function()
    if not activeTarget or not isElement(activeTarget) then
        return
    end

    local x, y, z = getElementPosition(activeTarget)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0.2)
    if sx and sy then
        exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_TARGET, { x = sx, y = sy })
    end
end)

addEvent(Events.INTERACTION_LIST_RECEIVED, true)
addEventHandler(Events.INTERACTION_LIST_RECEIVED, root, function(items)
    exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_LIST, items)
end)

-- Relayed through core_ui's ui:notify channel (see Transport.lua's module
-- comment) - `key` arrives already JSON-decoded back into a real string.
addEvent(Events.INTERACTION_ACTIVATED, true)
addEventHandler(Events.INTERACTION_ACTIVATED, root, function(key)
    if not activeTarget or not isElement(activeTarget) then
        return
    end
    triggerServerEvent(Events.INTERACTION_CALL, resourceRoot, activeTarget, key)
end)

addEventHandler("onClientVehicleEnter", root, function(player)
    if player == localPlayer and lookingForInteractions then
        closeInteractionMode()
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if lookingForInteractions then
        closeInteractionMode()
    end
end)
