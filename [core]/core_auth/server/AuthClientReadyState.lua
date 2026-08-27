-- Tracks which players' core_auth CLIENT scripts have actually loaded -
-- see Events.AUTH_CLIENT_READY's own comment in Events.lua for why this
-- is a separate signal from core_bootstrap's server-side chain-ready
-- state. Same pattern as core_ui/server/BrowserReadyHandler.lua.

local readyPlayers = {}

addEvent(Events.AUTH_CLIENT_READY, true)
addEventHandler(Events.AUTH_CLIENT_READY, root, function()
    readyPlayers[client] = true
end)

addEventHandler("onPlayerQuit", root, function()
    readyPlayers[source] = nil
end)

--- @param player element
-- @return boolean
function authClientReadyIsReady(player)
    return readyPlayers[player] == true
end
