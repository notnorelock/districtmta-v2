-- Listens for Events.ITEM_PICKUP, fired by gm_interactions' generic
-- "object:itemPickup" InteractionRegistry entry (see that file's own
-- module comment on why the interaction itself can't call directly into
-- gm_items - a handler function can't cross the resource boundary).
-- Fired via plain triggerEvent (server-to-server, gm_interactions ->
-- gm_items), not triggerServerEvent/triggerClientEvent.
addEvent(Events.ITEM_PICKUP, true)
addEventHandler(Events.ITEM_PICKUP, root, function(player, itemId)
    if not isElement(player) or getElementType(player) ~= "player" then
        return
    end
    if type(itemId) ~= "number" then
        return
    end

    ItemService.pickup(player, itemId)
end)
