-- Tracks which players' CEF frontend has finished booting.
UiState = UiState or {}

local readyPlayers = {}

addEvent(Events.BROWSER_READY, true)
addEventHandler(Events.BROWSER_READY, root, function()
    readyPlayers[client] = true
    outputServerLog("[DEBUG][core_ui] BROWSER_READY server handler fired for " .. tostring(isElement(client) and getPlayerName(client) or "?"))
    Logger.debug("core_ui", "Browser reported ready", { player = getPlayerName(client) })
end)

addEventHandler("onPlayerQuit", root, function()
    readyPlayers[source] = nil
end)

--- @param player element
-- @return boolean
UiState.isBrowserReady = function(player)
    return readyPlayers[player] == true
end

function uiStateIsBrowserReady(player)
    return UiState.isBrowserReady(player)
end
