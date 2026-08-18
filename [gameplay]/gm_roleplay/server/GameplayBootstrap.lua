-- gm_roleplay's only UI-adjacent responsibility: spawnPlayer + camera
-- fade, called by core_auth once a spawn location is confirmed - see
-- docs/Architecture.md's account lifecycle section.

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

    fadeCamera(player, true)
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
