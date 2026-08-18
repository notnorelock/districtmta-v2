-- Delivers core's per-player session key to the client, retrying briefly
-- if core hasn't issued it yet (onPlayerJoin ordering across resources
-- isn't guaranteed).
--
-- The event name itself is per-player and derived from getPlayerSerial
-- (sha256, never sent over the wire) rather than a fixed literal - a
-- fixed name like "sessionKey" is a one-line addEventHandler away for
-- anything running client-side (a lua exec, an injected script) to sniff
-- the key before it even reaches the browser. Deriving the name instead
-- means both sides compute the same string independently - client-side
-- via getPlayerSerial() (no args = local player's own serial), server-side
-- via getPlayerSerial(player) - so nothing needed to find the channel is
-- ever transmitted. This is still just friction, not real security - see
-- docs/UiBridge.md's "Payload obfuscation" section; the actual security
-- boundary is FetchBridge's server-side validation, unaffected either way.
local function sessionKeyEventName(player)
    return "sk:" .. sha256(getPlayerSerial(player))
end

local MAX_ATTEMPTS = 5
local RETRY_DELAY_MS = 200

local function deliverSessionKey(player, attempt)
    if not isElement(player) then
        return
    end

    local key = exports.core:getSessionKey(player)

    if key then
        local eventName = sessionKeyEventName(player)
        addEvent(eventName, true)
        triggerClientEvent(player, eventName, resourceRoot, key)
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
