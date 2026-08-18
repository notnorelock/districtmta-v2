-- Opens the auth UI window when the server signals a player needs to
-- authenticate, and closes it once the server confirms world entry.
-- SPAWN_SELECT_CLOSE only flags the window as pending-close rather than
-- closing it immediately - it waits for onClientPlayerSpawn so the player
-- sees a loading state through the spawn itself rather than a jarring cut.

addEvent(Events.AUTH_BEGIN_AUTHENTICATION, true)
addEventHandler(Events.AUTH_BEGIN_AUTHENTICATION, root, function()
    UI.open(Enums.UiWindow.AUTHENTICATION)
end)

addEvent(Events.AUTH_SUCCESS_AUTHENTICATION, true)
addEventHandler(Events.AUTH_SUCCESS_AUTHENTICATION, root, function()
    UI.close(Enums.UiWindow.AUTHENTICATION)
end)

addEvent(Events.SPAWN_SELECT_OPEN, true)
addEventHandler(Events.SPAWN_SELECT_OPEN, root, function()
    UI.open(Enums.UiWindow.SPAWN_SELECT)
end)

local spawnSelectClosePending = false
local playerSpawnedOnce = false

addEvent(Events.SPAWN_SELECT_CLOSE, true)
addEventHandler(Events.SPAWN_SELECT_CLOSE, root, function()
    if playerSpawnedOnce then
        UI.close(Enums.UiWindow.SPAWN_SELECT)
        playerSpawnedOnce = false
        return
    end
    spawnSelectClosePending = true
end)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    if spawnSelectClosePending then
        UI.close(Enums.UiWindow.SPAWN_SELECT)
        spawnSelectClosePending = false
        return
    end
    playerSpawnedOnce = true
end)
