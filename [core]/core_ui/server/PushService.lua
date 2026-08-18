-- Server -> client push channel, separate from FetchBridge's request/response RPC.
PushService = PushService or {}

--- Pushes an event to a single player's browser.
-- @param player element
-- @param event string push event name (see Events.PUSH_*)
-- @param data any JSON-serializable payload
PushService.send = function(player, event, data)
    if not isElement(player) then
        return
    end
    triggerClientEvent(player, Events.UI_PUSH_EVENT, resourceRoot, event, data)
end

--- Pushes an event to every connected player.
-- @param event string
-- @param data any
PushService.broadcast = function(event, data)
    for _, player in ipairs(getElementsByType("player")) do
        PushService.send(player, event, data)
    end
end

function pushServiceSend(player, event, data) PushService.send(player, event, data) end
function pushServiceBroadcast(event, data) PushService.broadcast(event, data) end
