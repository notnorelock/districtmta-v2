-- Radar blips for other players in the local player's own interior/
-- dimension. Vehicle blips (private-vehicle ownership) and per-group/
-- wanted-level blip coloring from the old version of this file are
-- deliberately NOT ported - vehicle:owner/vehicle:purpose and
-- player:duty/player:wanted have no real system behind them in this
-- project yet (see the TODO below); porting fake-looking logic for
-- systems that don't exist would just be dead weight until they do.
PlayerBlips = PlayerBlips or {}

local BLIP_ICON_DEFAULT = 8
local BLIP_VISIBLE_DISTANCE = 300
local UPDATE_INTERVAL_MS = 5000

local blips = {}

--- @param player element
-- @return boolean whether `player` should currently have a blip - same
--         interior/dimension as localPlayer, spawned, and not invisible
--         (getElementAlpha 0 - e.g. an admin's /vanish or similar).
local function shouldHaveBlip(player)
    return getElementData(player, ElementData.Player.SPAWNED) == true
        and getElementInterior(player) == getElementInterior(localPlayer)
        and getElementDimension(player) == getElementDimension(localPlayer)
        and getElementAlpha(player) ~= 0
end

--- Removes and forgets the blip for `player`, if one exists.
-- @param player element
local function removeBlip(player)
    local blip = blips[player]
    if blip then
        if isElement(blip) then
            destroyElement(blip)
        end
        blips[player] = nil
    end
end

--- Creates the blip for `player`. Assumes shouldHaveBlip(player) already
--- passed and blips[player] doesn't exist yet.
-- @param player element
local function addBlip(player)
    -- TODO: once a group/gang-duty or wanted-level system exists, branch
    -- the icon/color/visible-distance here the way the old version of
    -- this file did (player:duty.group match -> icon 3 + 1.5x distance,
    -- player:wanted -> icon 7 vs 8). Until then every player blip looks
    -- the same - see this file's module comment.
    blips[player] = createBlipAttachedTo(player, BLIP_ICON_DEFAULT, 2, 255, 0, 0, getElementAlpha(player))
    setBlipVisibleDistance(blips[player], BLIP_VISIBLE_DISTANCE)
end

--- Full resync - drops blips for players who no longer qualify, creates
--- blips for players who now do. Cheap enough to run on a timer
--- (getElementsByType("player") is never more than the server's player
--- cap), and simpler/more robust against missed events than trying to
--- track every interior/dimension/spawn/alpha change individually.
PlayerBlips.update = function()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end

    for player in pairs(blips) do
        if not isElement(player) or not shouldHaveBlip(player) then
            removeBlip(player)
        end
    end

    for _, player in ipairs(getElementsByType("player")) do
        if player ~= localPlayer and not blips[player] and shouldHaveBlip(player) then
            addBlip(player)
        end
    end
end

addEventHandler("onClientPlayerQuit", root, function()
    removeBlip(source)
end)

setTimer(PlayerBlips.update, UPDATE_INTERVAL_MS, 0)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for player in pairs(blips) do
        removeBlip(player)
    end
end)
