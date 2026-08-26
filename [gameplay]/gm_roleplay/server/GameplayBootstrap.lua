-- gm_roleplay's only UI-adjacent responsibility: spawnPlayer + camera
-- fade, called by core_auth once a spawn location is confirmed - see
-- docs/Architecture.md's account lifecycle section.

-- Slow, cinematic fade-in from black on spawn (rather than MTA's own
-- ~1s default) so the player's character is smoothly revealed instead of
-- popping into view - see enterWorld's own fadeCamera call below. The
-- server-side fadeCamera(player, fadeIn, time, ...) signature accepts
-- this duration directly, no client-side timer/effect needed.
local CAMERA_FADE_IN_SECONDS = 5.0

--- Spawns `player` at `location` and fades the camera in.
-- @param player element
-- @param location table { x, y, z, interior, dimension, skin, id, ... }
local function enterWorld(player, location)
    if not player or not isElement(player) then
        return
    end

    local model = getElementData(player, ElementData.Player.SKIN) or 0

    spawnPlayer(player, location.x, location.y, location.z, 0, model, location.interior, location.dimension)
    setElementModel(player, model)
    setElementInterior(player, location.interior)
    setElementDimension(player, location.dimension)

    fadeCamera(player, true, CAMERA_FADE_IN_SECONDS)
    setCameraTarget(player, player)
    
    setElementData(player, ElementData.Player.SPAWNED, true)

    outputServerLog(string.format(
        "[INFO] [gm_roleplay] Player entered world (player=%s, spawn=%s)",
        getPlayerName(player), tostring(location.id)
    ))
end

function gameplayEnterWorld(player, location)
    enterWorld(player, location)
end
