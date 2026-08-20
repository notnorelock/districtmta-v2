-- World interaction: E toggles a "looking for interactions" mode - NO
-- cursor at all (back to this from an earlier click-driven design per
-- explicit user request). While active: every interactable player/
-- vehicle/object in range is outlined via WallShader.lua, and whichever
-- one is most directly IN FRONT OF THE PLAYER (smallest angle between the
-- player's own facing direction and the vector to the candidate) becomes
-- the active target automatically - its interaction list is requested
-- and the CEF overlay's pointer diamond/line + option list appear for
-- it. Scroll wheel moves the list selection, space activates. Both are
-- swallowed with cancelEvent() (see the onClientKey handler below) so
-- they don't ALSO cycle weapons / pull the handbrake underneath.
--
-- Targeting is based on the PLAYER's own position/facing (getElementPosition/
-- getElementRotation), not the camera - an earlier screen-center-distance
-- version used getCameraMatrix/getScreenFromWorldPosition instead, which
-- meant swinging the camera around (without turning the character, e.g.
-- MTA's default third-person free-look) could target something the
-- player's own model isn't even facing. This way the target only changes
-- when the character actually turns, matching what's in front of them.
WorldInteractionState = WorldInteractionState or {}

local SCAN_INTERVAL_MS = 150
local RANGE = 10 -- world-space candidate radius; InteractionService.lua re-validates the real per-type range server-side regardless
-- WallShader's own outline uses this wider cone (everything the player
-- could plausibly be about to turn onto) - MAX_TARGET_ANGLE_DEG (the
-- narrower cone the actual ACTIVE target is picked from) stays tighter
-- so the target doesn't flicker between two outlined candidates sitting
-- side by side.
local OUTLINE_ANGLE_DEG = 70
local MAX_TARGET_ANGLE_DEG = 45 -- ignore candidates more than this many degrees off the player's facing direction

-- Hysteresis margin for the outline set: an already-outlined candidate
-- only drops out once it's past RANGE/OUTLINE_ANGLE_DEG by this much, not
-- the instant it crosses the exact threshold. Without this, a candidate
-- sitting right at the edge of either threshold flickered on/off every
-- scan tick as the player's own position/facing wobbled slightly while
-- walking (the walk animation's own subtle sway, footstep-to-footstep
-- position drift) - each tiny wobble flipped it in and out of range/cone
-- and WallShader's outline toggled with it. A NEW candidate (not already
-- outlined) still has to clear the tighter, non-relaxed threshold first -
-- only candidates already showing get the wider one to leave by.
local OUTLINE_RANGE_HYSTERESIS = 1.5
local OUTLINE_ANGLE_HYSTERESIS = 12

-- MTA can fire mouse_wheel_up/down more than once per physical wheel
-- click - same lesson gm_radio/client/RadioState.lua's own
-- SCROLL_DELAY_MS documents. Without this, a single scroll click could
-- move the selection by 2+ items at once and made the CSS transform
-- transition (see WorldInteractionOverlay.module.scss's .list) restart
-- mid-animation repeatedly, reading as the whole list shaking.
local SCROLL_DELAY_MS = 90
local lastScrollTick = 0

local lookingForInteractions = false
local activeTarget = nil -- element the CEF list is currently showing for, nil if none in view
local outlinedElements = {} -- element -> true, currently outlined by WallShader (see OUTLINE_*_HYSTERESIS above)

--- @return element[] every player/vehicle/object worth considering as a candidate
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

--- @param element element
-- @return boolean true if same interior+dimension as localPlayer
local function sameZone(element)
    return getElementDimension(localPlayer) == getElementDimension(element)
        and getElementInterior(localPlayer) == getElementInterior(element)
end

--- @return number, number the player's own horizontal facing vector
--         (normalized) - MTA's own GetPositionInFrontOfElement wiki
--         reference formula: objX = x - distance*sin(rad), objY =
--         y + distance*cos(rad), i.e. the facing vector is
--         (-sin(rad), cos(rad)), NOT (sin(rad), cos(rad)).
local function playerFacingVector()
    local _, _, facingDeg = getElementRotation(localPlayer)
    local facingRad = math.rad(facingDeg)
    return -math.sin(facingRad), math.cos(facingRad)
end

--- @param px number player X
-- @param py number player Y
-- @param facingX number player's facing vector X (see playerFacingVector)
-- @param facingY number player's facing vector Y
-- @param x number candidate X
-- @param y number candidate Y
-- @return number|nil degrees off the player's facing direction (0 =
--         directly ahead, 180 = directly behind), nil if the candidate
--         sits essentially on top of the player (no meaningful direction)
local function angleFromFacing(px, py, facingX, facingY, x, y)
    local dx, dy = x - px, y - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.01 then
        return nil
    end

    -- Dot product of two normalized vectors = cos(angle between them).
    local dot = (facingX * dx + facingY * dy) / dist
    return math.deg(math.acos(math.max(-1, math.min(1, dot))))
end

--- @return element[] nearby, same-zone, in-range, roughly-in-front-of-
--         the-player candidates - outlined by WallShader (see
--         OUTLINE_ANGLE_DEG's own comment on why this cone is wider than
--         MAX_TARGET_ANGLE_DEG's own, tighter one). Elements already in
--         outlinedElements get the relaxed OUTLINE_*_HYSTERESIS
--         thresholds to leave by (see its own comment) - updates
--         outlinedElements itself before returning.
local function rangeFilteredCandidates()
    local px, py, pz = getElementPosition(localPlayer)
    local facingX, facingY = playerFacingVector()
    local list = {}
    local nextOutlined = {}

    for _, element in ipairs(nearbyElements()) do
        if sameZone(element) then
            local x, y, z = getElementPosition(element)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local angle = angleFromFacing(px, py, facingX, facingY, x, y)

            local rangeLimit, angleLimit = RANGE, OUTLINE_ANGLE_DEG
            if outlinedElements[element] then
                rangeLimit = RANGE + OUTLINE_RANGE_HYSTERESIS
                angleLimit = OUTLINE_ANGLE_DEG + OUTLINE_ANGLE_HYSTERESIS
            end

            if dist <= rangeLimit and (angle == nil or angle <= angleLimit) then
                list[#list + 1] = element
                nextOutlined[element] = true
            end
        end
    end

    outlinedElements = nextOutlined
    return list
end

-- LOS is only checked past this distance - closer than that, the ray
-- from the player to the candidate's own position frequently clips the
-- candidate's OWN collision (its position is inside its own bounding
-- box, e.g. a vehicle's origin sits inside its body), making
-- isLineOfSightClear report "blocked" by the very thing it's a ray
-- towards - self-occlusion, not an actual obstruction. MTA's
-- isLineOfSightClear has no "ignore this element" parameter, so instead
-- of fighting that, LOS just isn't checked at all in this close range -
-- interaction range itself (RANGE, above) is small enough that something
-- ELSE fully blocking the view at this distance is rare.
local LOS_CHECK_MIN_DISTANCE = 6

--- Picks the in-range candidate the player is most directly facing -
--- smallest angle between the player's own facing direction (their
--- rotation) and the horizontal vector toward the candidate, within
--- MAX_TARGET_ANGLE_DEG. LOS is only re-checked for candidates past
--- LOS_CHECK_MIN_DISTANCE (see its own comment).
-- @param candidates element[]
-- @return element|nil
local function mostInFrontOfPlayer(candidates)
    local px, py, pz = getElementPosition(localPlayer)
    local facingX, facingY = playerFacingVector()

    local best, bestAngle = nil, MAX_TARGET_ANGLE_DEG

    for _, element in ipairs(candidates) do
        local x, y, z = getElementPosition(element)
        local angle = angleFromFacing(px, py, facingX, facingY, x, y)

        if angle ~= nil and angle < bestAngle then
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local sightClear = dist <= LOS_CHECK_MIN_DISTANCE
                or isLineOfSightClear(px, py, pz + 0.6, x, y, z, true, true, false, true, true, true)

            if sightClear then
                best, bestAngle = element, angle
            end
        end
    end

    return best
end

local lastListRequestTarget = nil

--- Requests the interaction list for `element` from the server, unless
--- already the last-requested target (avoids re-requesting every scan
--- tick while looking at the same thing).
-- @param element element|nil
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

--- Rebuilds the candidate set (nearby, same-zone, in-range elements),
--- syncs WallShader's outline to match, and re-picks the facing target -
--- called on a timer while lookingForInteractions, not every frame
--- (outline set / target changing a few times a second is imperceptible,
--- re-scanning every element every frame is not free).
local function refreshCandidates()
    if not lookingForInteractions then
        return
    end

    local candidates = rangeFilteredCandidates()
    toggleWallShader(true, candidates)

    local target = mostInFrontOfPlayer(candidates)
    if target ~= activeTarget then
        activeTarget = target
        requestListFor(target)
    end
end

local function openInteractionMode()
    if lookingForInteractions then
        return
    end
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end
    if isPedInVehicle(localPlayer) then
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

    exports.core_ui:uiHideOverlay("worldInteraction")
end

local function toggleInteractionMode()
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

    -- Scroll/space must be swallowed with cancelEvent() while in this
    -- mode, same lesson VehicleInteractionState.lua's own module comment
    -- documents for its radial menu - without it, scrolling ALSO cycles
    -- weapons underneath the list, and space ALSO pulls the handbrake/jumps.
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
        -- onClientKey can only cancel a bind on the DOWN press, not the
        -- up/release (per MTA's own docs) - fine here since `state ==
        -- false` never activates anything below anyway.
        cancelEvent()
        if state and activeTarget then
            exports.core_ui:uiPushEvent(Events.PUSH_INTERACTION_ACTIVATE, true)
        end
    end
end)

setTimer(refreshCandidates, SCAN_INTERVAL_MS, 0)

-- Target screen position is pushed every render frame (not the scan
-- timer) so the pointer diamond/line track it smoothly - same
-- "candidate list on a timer, per-frame draw" split gm_3dtext uses.
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

--- The frontend confirms which item it activated (its own current
--- selection) via this - see WorldInteractionOverlay.tsx's onActivate.
addEvent(Events.INTERACTION_ACTIVATED, true)
addEventHandler(Events.INTERACTION_ACTIVATED, root, function(key)
    if not activeTarget or not isElement(activeTarget) then
        return
    end
    triggerServerEvent(Events.INTERACTION_CALL, resourceRoot, activeTarget, key)
end)

-- Entering a vehicle while in interaction mode just closes it, same as
-- the radial vehicle menu closing on vehicle exit.
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
