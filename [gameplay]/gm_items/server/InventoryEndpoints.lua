-- Client -> server event handlers for the inventory panel (I) - each one
-- re-derives ownership/validity itself via ItemService before doing
-- anything, never trusts the panel's own belief that an action is valid
-- (the panel can only show what ItemService already told it via
-- PUSH_INVENTORY_ITEMS, but a modified client could send any itemId).
addEvent(Events.INVENTORY_REQUEST_ITEMS, true)
addEventHandler(Events.INVENTORY_REQUEST_ITEMS, root, function()
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end
    ItemService.sync(client)
end)

addEvent(Events.INVENTORY_USE_ITEM, true)
addEventHandler(Events.INVENTORY_USE_ITEM, root, function(itemId)
    if type(itemId) ~= "number" then
        return
    end
    ItemService.use(client, itemId)
end)

addEvent(Events.INVENTORY_DROP_ITEM, true)
addEventHandler(Events.INVENTORY_DROP_ITEM, root, function(itemId)
    if type(itemId) ~= "number" then
        return
    end
    ItemService.drop(client, itemId)
end)

addEvent(Events.INVENTORY_TOGGLE_FAVORITE, true)
addEventHandler(Events.INVENTORY_TOGGLE_FAVORITE, root, function(itemId)
    if type(itemId) ~= "number" then
        return
    end
    ItemService.toggleFavorite(client, itemId)
end)
