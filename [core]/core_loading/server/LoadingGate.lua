-- Fires Events.LOADING_READY for a player once ALL THREE of:
--   1. core_bootstrap's chain has finished (bootstrapIsChainReady) -
--      every server-side resource in START_ORDER has started.
--   2. that player's CEF frontend has reported ready (uiStateIsBrowserReady) -
--      the SolidJS app actually mounted, not just the HTML document loaded.
--   3. that player's own core_auth CLIENT scripts have loaded
--      (authClientReadyIsReady) - core_bootstrap's chain only proves
--      core_auth's SERVER half started, not that this specific player's
--      client has finished downloading/executing AuthUiClient.lua yet.
-- core_auth/server/AuthUiController.lua waits on this instead of opening
-- the auth window straight from onPlayerJoin. Polls rather than wiring a
-- precise event chain, since there are enough interleavings (join during
-- boot, any side finishing first, restarts mid-session) that a short
-- poll per not-yet-ready player is simpler and just as correct as
-- covering them all with events - each of the three ready-signals above
-- also forces an immediate poll() on arrival (see the DOWNLOAD_FINISHED/
-- AUTH_CLIENT_READY handlers below) so the poll interval is just a
-- fallback, not the only way LOADING_READY ever fires.

local POLL_INTERVAL_MS = 200

-- This resource owns Events.LOADING_READY, so addEvent is called here before any triggerEvent.
addEvent(Events.LOADING_READY, true)
-- Client -> server, fired by core_loading/client/DownloadTracker.lua once
-- MTA's own transfer box reports downloads are done - lets a poll() run
-- immediately instead of waiting up to POLL_INTERVAL_MS for the next tick.
addEvent(Events.DOWNLOAD_FINISHED, true)
-- Owned/added by core_auth/server/AuthClientReadyState.lua, but
-- addEventHandler below needs addEvent to have run IN THIS RESOURCE'S
-- OWN load order too (a second addEvent call for the same name is a
-- harmless no-op in MTA, not an error - see BrowserManager.lua's own
-- comment on this same pattern for Events.BROWSER_READY).
addEvent(Events.AUTH_CLIENT_READY, true)

local readyFired = {}
local pollTimers = {}

local function isBrowserReady(player)
    local browserOk, browserReady = pcall(function()
        return exports.core_ui:uiStateIsBrowserReady(player)
    end)
    return browserOk and browserReady == true
end

local function isChainReady()
    local chainOk, chainReady = pcall(function()
        return exports.core_bootstrap:bootstrapIsChainReady()
    end)
    return chainOk and chainReady == true
end

-- "core_auth resource started" (already covered by isChainReady) only
-- means the SERVER half of core_auth is up - it says nothing about
-- whether THIS player's own client has finished downloading/executing
-- core_auth's client scripts yet (AuthUiClient.lua's own addEvent calls
-- included). Without this, AuthUiController.lua's LOADING_READY handler
-- could triggerClientEvent(AUTH_BEGIN_AUTHENTICATION) before this
-- player's client had loaded that far, which MTA logs as "event is not
-- added clientside" and silently drops - see Events.AUTH_CLIENT_READY's
-- own comment.
local function isAuthClientReady(player)
    local authOk, authReady = pcall(function()
        return exports.core_auth:authClientReadyIsReady(player)
    end)
    return authOk and authReady == true
end

local function stopPolling(player)
    if pollTimers[player] and isTimer(pollTimers[player]) then
        killTimer(pollTimers[player])
    end
    pollTimers[player] = nil
end

-- Extracted from startPolling so Events.DOWNLOAD_FINISHED's handler
-- below can force an immediate check for a player instead of waiting up
-- to POLL_INTERVAL_MS for the next scheduled tick.
local function poll(player)
    if not isElement(player) then
        stopPolling(player)
        return
    end
    if readyFired[player] then
        return
    end

    local browserReady = isBrowserReady(player)
    local chainReady = isChainReady()
    local authClientReady = isAuthClientReady(player)

    if browserReady and chainReady and authClientReady then
        stopPolling(player)
        readyFired[player] = true
        setElementData(player, ElementData.Player.LOADING_READY, true)
        triggerEvent(Events.LOADING_READY, player)
        outputServerLog(string.format("[INFO] [core_loading] LOADING_READY fired (player=%s)", getPlayerName(player)))
    end
end

local function startPolling(player)
    if readyFired[player] or pollTimers[player] then
        return
    end

    poll(player)
    if not readyFired[player] then
        pollTimers[player] = setTimer(poll, POLL_INTERVAL_MS, 0, player)
    end
end

addEventHandler(Events.DOWNLOAD_FINISHED, root, function()
    outputServerLog(string.format("[INFO] [core_loading] DOWNLOAD_FINISHED received (player=%s), forcing immediate poll", getPlayerName(client)))
    poll(client)
end)

-- core_auth itself owns/fires Events.AUTH_CLIENT_READY (see
-- AuthClientReadyState.lua) - this resource just needs its own
-- addEventHandler on it to force an immediate poll() the moment it
-- arrives, same reasoning as the DOWNLOAD_FINISHED handler above.
addEventHandler(Events.AUTH_CLIENT_READY, root, function()
    outputServerLog(string.format("[INFO] [core_loading] AUTH_CLIENT_READY received (player=%s), forcing immediate poll", getPlayerName(client)))
    poll(client)
end)

addEventHandler("onPlayerJoin", root, function()
    startPolling(source)
end)

-- A player already connected when this resource (re)starts mid-session also
-- needs (re-)checking - onPlayerJoin only fires once, at connect time.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        startPolling(player)
    end
    setTransferBoxVisible (false)
end)

addEventHandler("onPlayerQuit", root, function()
    stopPolling(source)
    readyFired[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(pollTimers) do
        stopPolling(player)
    end
    readyFired = {}
end)
