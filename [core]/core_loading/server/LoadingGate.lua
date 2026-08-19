-- Fires Events.LOADING_READY for a player once core_bootstrap's chain has
-- finished (bootstrapIsChainReady) AND that player's CEF frontend has
-- reported ready (uiStateIsBrowserReady). core_auth/server/AuthUiController.lua
-- waits on this instead of opening the auth window straight from onPlayerJoin.
-- Polls rather than wiring a precise event chain, since there are enough
-- interleavings (join during boot, either side finishing first, restarts
-- mid-session) that a short poll per not-yet-ready player is simpler and
-- just as correct as covering them all with events.

local POLL_INTERVAL_MS = 200

-- This resource owns Events.LOADING_READY, so addEvent is called here before any triggerEvent.
addEvent(Events.LOADING_READY, true)

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

local function stopPolling(player)
    if pollTimers[player] and isTimer(pollTimers[player]) then
        killTimer(pollTimers[player])
    end
    pollTimers[player] = nil
end

local function startPolling(player)
    if readyFired[player] or pollTimers[player] then
        return
    end

    local function poll()
        if not isElement(player) then
            stopPolling(player)
            return
        end

        local browserReady = isBrowserReady(player)
        local chainReady = isChainReady()

        if browserReady and chainReady then
            stopPolling(player)
            readyFired[player] = true
            setElementData(player, ElementData.Player.LOADING_READY, true)
            triggerEvent(Events.LOADING_READY, player)
            outputServerLog(string.format("[INFO] [core_loading] LOADING_READY fired (player=%s)", getPlayerName(player)))
        end
    end

    poll()
    if not readyFired[player] then
        pollTimers[player] = setTimer(poll, POLL_INTERVAL_MS, 0)
    end
end

addEventHandler("onPlayerJoin", root, function()
    startPolling(source)
end)

-- A player already connected when this resource (re)starts mid-session also
-- needs (re-)checking - onPlayerJoin only fires once, at connect time.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        startPolling(player)
    end
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
