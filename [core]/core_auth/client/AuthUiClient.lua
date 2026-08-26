local function noop()
    if isChatVisible() then
        showChat(false)
    end
end

addEvent(Events.AUTH_BEGIN_AUTHENTICATION, true)
addEventHandler(Events.AUTH_BEGIN_AUTHENTICATION, root, function()
    UI.open(Enums.UiWindow.AUTHENTICATION)
    showChat(false)
    addEventHandler("onClientRender", root, noop)
end)

addEvent(Events.AUTH_ALREADY_IN_WORLD, true)
addEventHandler(Events.AUTH_ALREADY_IN_WORLD, root, function()
    exports.core_ui:uiPushEvent(Events.PUSH_UI_ALREADY_IN_WORLD, true)
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
    showChat(true)
    removeEventHandler("onClientRender", root, noop)
    playerSpawnedOnce = true
end)
