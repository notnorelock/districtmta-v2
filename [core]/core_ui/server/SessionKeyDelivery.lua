-- Delivers core's per-player session key to the client, retrying briefly
-- if core hasn't issued it yet (onPlayerJoin ordering across resources
-- isn't guaranteed).
local SESSION_KEY_EVENT = "sessionKey"
addEvent(SESSION_KEY_EVENT, true)

local MAX_ATTEMPTS = 5
local RETRY_DELAY_MS = 200

local function deliverSessionKey(player, attempt)
    if not isElement(player) then
        return
    end

    local key = exports.core:getSessionKey(player)

    if key then
        triggerClientEvent(player, SESSION_KEY_EVENT, resourceRoot, key)
        Logger.debug("SessionKeyDelivery", "Session key delivered", { player = getPlayerName(player) })
        return
    end

    attempt = attempt or 1
    if attempt >= MAX_ATTEMPTS then
        Logger.warn("SessionKeyDelivery", "Gave up waiting for core to issue a session key", { player = getPlayerName(player) })
        return
    end

    setTimer(function()
        deliverSessionKey(player, attempt + 1)
    end, RETRY_DELAY_MS, 1)
end

addEventHandler("onPlayerJoin", root, function()
    deliverSessionKey(source)
end)

-- onPlayerJoin only fires at actual connection time - if core_ui restarts
-- while a player is already connected (the common dev/test workflow),
-- that handler never fires again and the client's session key (reset by
-- the browser being recreated on this resource's own restart) would
-- never be redelivered without this.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        deliverSessionKey(player)
    end
end)
