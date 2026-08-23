-- Player inventories + world-dropped items: loading/saving a player's own
-- item rows, giving/taking/using/dropping/picking up, and carry-weight
-- enforcement. Ported from an older, unrelated project's reference
-- implementation (pd_items), cut down to Enums.ItemType.PLAIN/VEHICLE_KEY
-- only - see ItemSchemes.lua's own module comment on scope.
--
-- Unlike the reference implementation (which kept a player's item list in
-- player:items element data, publicly readable by every client), this
-- keeps each player's inventory in a server-only Lua table
-- (playerItems below) - element data is broadcast to every client that
-- can see the element, which would leak one player's full inventory
-- contents to everyone nearby. Only the owning client is ever told its
-- own contents, via INVENTORY_ITEMS_RECEIVED/PUSH_INVENTORY_ITEMS.
ItemService = ItemService or {}

local SAVE_INTERVAL_MS = 60000 * 5

-- Tells core/server/database/repositories/ItemRepository.lua "write SQL
-- NULL for this column" - must match that file's own NULL_SENTINEL
-- constant exactly (a plain string, not Model.NULL itself: gm_items has
-- no access to Model.NULL, and even if it did, MTA's triggerEvent copies
-- table arguments across the resource boundary rather than preserving
-- reference identity, so Model.NULL's own `==` sentinel trick wouldn't
-- survive the trip - see ItemRepository.lua's own comment on this).
local NULL_SENTINEL = "__ITEM_REPOSITORY_NULL__"

-- player -> { { id, schemeKey, amount, itemValues, flags, favorite }, ... }
-- in ipairs-safe array order. This is the single source of truth for a
-- connected player's inventory - always mutate this table and re-sync,
-- never the other way around.
local playerItems = {}

-- object (world-dropped item element) -> items row id
local worldItemObjects = {}
-- items row id -> { object, item } - the reverse of worldItemObjects (so
-- ItemService.pickup can look up the object from just the id
-- gm_interactions hands back) PLUS the row's own carried-over item data
-- (item = { id, schemeKey, amount, itemValues, flags, favorite }, see
-- itemFromRow below), so pickup doesn't need a round trip to the
-- database just to learn what it's about to hand the player (a dropped
-- stack's amount, a dropped vehicle key's itemValues, etc. - these must
-- survive the drop -> world -> pickup round trip unchanged).
local worldItemsById = {}

--- @param player element
-- @return table[] `player`'s own item list (never nil - defaults to {} on first read)
ItemService.itemsOf = function(player)
    return playerItems[player] or {}
end

--- @param player element
-- @param vehicleId number a gm_vehicles database row id (ElementData.Vehicle.ID)
-- @return boolean true if `player` is carrying a VEHICLE_KEY item whose
--         itemValues[1] == vehicleId - used by gm_interactions'
--         "vehicle:toggleLock" entry to gate who can lock/unlock a
--         vehicle via the world interaction menu (owner-only, same
--         itemValues shape ItemUseHandlers.lua's own VEHICLE_KEY handler reads).
ItemService.hasVehicleKey = function(player, vehicleId)
    for _, item in ipairs(ItemService.itemsOf(player)) do
        local scheme = ItemSchemes.get(item.schemeKey)
        if scheme and scheme.type == Enums.ItemType.VEHICLE_KEY and item.itemValues[1] == vehicleId then
            return true
        end
    end
    return false
end

function itemServiceHasVehicleKey(player, vehicleId)
    return ItemService.hasVehicleKey(player, vehicleId)
end

--- @param player element
-- @param kind string "gained" | "lost"
-- @param schemeKey string
-- @param amount number
local function pushItemToast(player, kind, schemeKey, amount)
    if not isElement(player) then
        return
    end
    triggerClientEvent(player, Events.ITEM_TOAST, player, { kind = kind, schemeKey = schemeKey, amount = amount })
end

--- Fire-and-forget cross-resource wrapper for ItemService.give - a
--- callback can never cross a resource boundary (see docs/Architecture.md's
--- "the one hard rule"), so this notifies `player` itself directly rather
--- than handing the caller a result to react to. A success pushes the
--- same "gained" item toast pickup/give use (see pushItemToast/ItemToast.tsx) -
--- a failure still goes through the plain native NotificationService
--- (a rejection isn't a "gain", the toast has nothing to show for it).
--- gm_vehicles' own VehicleCommands.lua calls this to hand a fresh
--- private vehicle's owner their VEHICLE_KEY - see that file's own
--- /createvehicle handler.
-- @param player element
-- @param schemeKey string
-- @param amount number
-- @param itemValues table|nil
function itemServiceGiveItem(player, schemeKey, amount, itemValues)
    if not isElement(player) then
        return
    end

    ItemService.give(player, schemeKey, amount, itemValues, function(ok)
        if not isElement(player) then
            return
        end
        if ok then
            pushItemToast(player, "gained", schemeKey, amount)
        else
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się dodać przedmiotu (za duży ciężar lub błąd)." })
        end
    end)
end

--- @param player element
-- @return number the current combined weight of player's carried items
ItemService.weightOf = function(player)
    local weight = 0
    for _, item in ipairs(ItemService.itemsOf(player)) do
        local scheme = ItemSchemes.get(item.schemeKey)
        if scheme then
            weight = weight + scheme.weight * item.amount
        end
    end
    return weight
end

-- Flat carry limit for now - no per-player/per-role variance exists yet
-- (no strength stat, no backpack/bag item system) - see this file's own
-- module comment on scope.
local MAX_WEIGHT = 20

--- @param player element
-- @return number
ItemService.maxWeightOf = function(player)
    return MAX_WEIGHT
end

--- Pushes `player`'s own current item list (plus their current/max carry
--- weight) into their CEF inventory panel.
-- @param player element
ItemService.sync = function(player)
    if not isElement(player) then
        return
    end
    triggerClientEvent(player, Events.INVENTORY_ITEMS_RECEIVED, player, {
        items = ItemService.itemsOf(player),
        weight = ItemService.weightOf(player),
        maxWeight = ItemService.maxWeightOf(player),
    })
end

--- @param row table an items table row (JSON columns already decoded by ItemRepository)
-- @return table the in-memory item shape playerItems/toEntry use
local function itemFromRow(row)
    return {
        id = row.id,
        schemeKey = row.scheme_key,
        amount = row.amount,
        itemValues = type(row.item_values) == "table" and row.item_values or {},
        flags = type(row.flags) == "table" and row.flags or {},
        favorite = row.favorite == true or row.favorite == 1,
    }
end

--- Loads `player`'s own items from the database into playerItems and
--- syncs the panel. Safe to call again later (e.g. a future re-login
--- flow) - always replaces the in-memory list wholesale.
-- @param player element
-- @param accountId number
ItemService.load = function(player, accountId)
    ItemBridge.call("findByOwnerAccountId", { accountId }, function(ok, rowsOrError)
        if not ok then
            Logger.error("ItemService", "Failed to load player items", { player = getPlayerName(player), error = tostring(rowsOrError) })
            return
        end
        if not isElement(player) then
            return
        end

        local items = {}
        for _, row in ipairs(rowsOrError) do
            items[#items + 1] = itemFromRow(row)
        end
        playerItems[player] = items

        ItemService.sync(player)
    end)
end

--- Persists every currently-loaded item row for `player` - only their
--- OWN mutable fields (amount/favorite; itemValues/flags rarely change
--- after creation but are included for completeness) are re-written,
--- never scheme/ownership (those don't change after creation/pickup).
-- @param player element
ItemService.save = function(player)
    local items = playerItems[player]
    if not items then
        return
    end

    for _, item in ipairs(items) do
        ItemBridge.call("update", { item.id, {
            amount = item.amount,
            favorite = item.favorite,
            item_values = item.itemValues,
            flags = item.flags,
        } }, function(ok, affectedOrError)
            if not ok then
                Logger.error("ItemService", "Failed to save item", { id = item.id, error = tostring(affectedOrError) })
            end
        end)
    end
end

--- @param player element
-- @param schemeKey string
-- @return table|nil, number|nil the FIRST stackable (maxStack ~= false,
--         amount < maxStack) item of this scheme, and its index
local function findStackable(player, schemeKey)
    local scheme = ItemSchemes.get(schemeKey)
    if not scheme or not scheme.maxStack then
        return nil
    end

    for index, item in ipairs(ItemService.itemsOf(player)) do
        if item.schemeKey == schemeKey and item.amount < scheme.maxStack then
            return item, index
        end
    end
    return nil
end

--- Gives `player` `amount` of `schemeKey` - stacks onto an existing,
--- not-yet-full stack if one exists and the scheme stacks, otherwise
--- creates a new row. Rejects if it would exceed MAX_WEIGHT.
-- @param player element
-- @param schemeKey string
-- @param amount number
-- @param itemValues table|nil
-- @param onComplete function(ok: boolean)|nil
ItemService.give = function(player, schemeKey, amount, itemValues, onComplete)
    onComplete = onComplete or function() end

    local scheme = ItemSchemes.get(schemeKey)
    if not scheme then
        Logger.warn("ItemService", "give: unknown scheme", { schemeKey = schemeKey })
        onComplete(false)
        return
    end

    if ItemService.weightOf(player) + scheme.weight * amount > ItemService.maxWeightOf(player) then
        onComplete(false)
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        onComplete(false)
        return
    end

    local stackable = findStackable(player, schemeKey)
    if stackable then
        stackable.amount = stackable.amount + amount
        ItemService.sync(player)
        onComplete(true)
        return
    end

    ItemBridge.call("create", {{
        owner_account_id = accountId,
        scheme_key = schemeKey,
        amount = amount,
        item_values = itemValues or {},
        flags = {},
        favorite = false,
    }}, function(ok, rowOrError)
        if not ok or not isElement(player) then
            if not ok then
                Logger.error("ItemService", "give: failed to create item row", { error = tostring(rowOrError) })
            end
            onComplete(false)
            return
        end

        local items = playerItems[player] or {}
        items[#items + 1] = itemFromRow(rowOrError)
        playerItems[player] = items

        ItemService.sync(player)
        onComplete(true)
    end)
end

--- @param player element
-- @param itemId number
-- @return table|nil, number|nil the item and its index in playerItems[player]
local function findOwnItem(player, itemId)
    for index, item in ipairs(ItemService.itemsOf(player)) do
        if item.id == itemId then
            return item, index
        end
    end
    return nil
end

--- Removes `amount` (or the whole stack, if nil) of item `itemId` from
--- `player`'s own inventory. Deletes the row entirely once its amount
--- reaches zero.
-- @param player element
-- @param itemId number
-- @param amount number|nil
-- @return boolean
ItemService.take = function(player, itemId, amount)
    local item, index = findOwnItem(player, itemId)
    if not item then
        return false
    end

    item.amount = item.amount - (amount or item.amount)

    if item.amount <= 0 then
        table.remove(playerItems[player], index)
        ItemBridge.call("delete", { itemId }, function(ok, affectedOrError)
            if not ok then
                Logger.error("ItemService", "take: failed to delete item row", { id = itemId, error = tostring(affectedOrError) })
            end
        end)
    end

    ItemService.sync(player)
    return true
end

--- Runs `itemId`'s scheme-specific effect for `player` - see
-- ItemUseHandlers.lua's ITEM_USE_HANDLERS for the per-type behavior.
-- @param player element
-- @param itemId number
ItemService.use = function(player, itemId)
    local item = findOwnItem(player, itemId)
    if not item then
        return
    end

    local scheme = ItemSchemes.get(item.schemeKey)
    if not scheme then
        return
    end

    local handler = ITEM_USE_HANDLERS[scheme.type]
    if handler then
        handler(player, item, scheme)
    end
end

-- x/y/z is always the dropping/loading player's own position (roughly
-- hip/chest height, not their feet) - getGroundPosition would be the
-- accurate fix but it's CLIENT-SIDE ONLY in MTA (confirmed live: "attempt
-- to call global 'getGroundPosition' (a nil value)" from this, a server
-- script - the server has no raycast-against-rendered-geometry API the
-- way the client does). A flat offset is an approximation (wrong on
-- stairs/slopes) but works everywhere server-side without an error.
local GROUND_OFFSET = 0.9

--- @param scheme ItemScheme
-- @param item table { id, schemeKey, amount, itemValues, flags, favorite } - carried over as-is, see worldItemsById's own comment
-- @return object|nil the spawned world object
local function spawnWorldObject(scheme, x, y, z, interior, dimension, item)
    local object = createObject(scheme.objectModel, x, y, z - GROUND_OFFSET)
    if not isElement(object) then
        return nil
    end

    setElementInterior(object, interior)
    setElementDimension(object, dimension)
    setElementData(object, ElementData.Item.ID, item.id)
    setElementData(object, ElementData.Item.SCHEME_KEY, item.schemeKey)

    -- No collisions: a dropped item sitting on the ground shouldn't block
    -- player/vehicle movement the way a normal world object would.
    setElementCollisionsEnabled(object, false)
    -- Tipped onto its side (90 degrees pitch) so it visually reads as a
    -- lying-on-the-ground pickup rather than standing upright in its
    -- model's default orientation - a random yaw keeps a pile of the same
    -- item from all looking identically aligned.
    setElementRotation(object, 90, 0, math.random(0, 359))

    worldItemObjects[object] = item.id
    worldItemsById[item.id] = { object = object, item = item }

    return object
end

--- Drops item `itemId` from `player`'s inventory as a world object at
--- their own current position. Removes it from their carried list either
--- way (partial-stack drops are not supported - the whole stack drops as
--- one new ownerless row, matching the reference implementation's own
--- dropPlayerItem behavior).
-- @param player element
-- @param itemId number
ItemService.drop = function(player, itemId)
    local item, index = findOwnItem(player, itemId)
    if not item then
        return
    end

    local scheme = ItemSchemes.get(item.schemeKey)
    if not scheme then
        return
    end

    if scheme.noDrop then
        return
    end

    local x, y, z = getElementPosition(player)
    local interior, dimension = getElementInterior(player), getElementDimension(player)

    ItemBridge.call("update", { itemId, {
        owner_account_id = NULL_SENTINEL,
        position = { x, y, z },
        interior = interior,
        dimension = dimension,
    } }, function(ok, affectedOrError)
        if not ok then
            Logger.error("ItemService", "drop: failed to update item row", { id = itemId, error = tostring(affectedOrError) })
            return
        end

        spawnWorldObject(scheme, x, y, z, interior, dimension, item)
    end)

    table.remove(playerItems[player], index)
    ItemService.sync(player)

    pushItemToast(player, "lost", item.schemeKey, item.amount)
end

--- Picks up world item `itemId` (its object must still exist) into
--- `player`'s own inventory - re-validated range against the object's
--- OWN current position, not whatever the client believes.
-- @param player element
-- @param itemId number
-- @return boolean
ItemService.pickup = function(player, itemId)
    local entry = worldItemsById[itemId]
    local object = entry and entry.object
    if not object or not isElement(object) then
        return false
    end

    local px, py, pz = getElementPosition(player)
    local ox, oy, oz = getElementPosition(object)
    if getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz) > 5 then
        return false
    end

    local scheme = ItemSchemes.get(entry.item.schemeKey)
    if not scheme then
        return false
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return false
    end

    if ItemService.weightOf(player) + scheme.weight > ItemService.maxWeightOf(player) then
        return false
    end

    -- Claimed immediately (before the database confirms) so a second,
    -- near-simultaneous pickup attempt on the same object - either by
    -- this player double-activating, or another player targeting the
    -- same item - can't also pass the isElement(object) check above and
    -- race this one. worldItemsById[itemId] is only really needed for
    -- id->object lookup; removing it here is what makes that check fail
    -- for anyone else from this point on, not the eventual destroyElement.
    worldItemObjects[object] = nil
    worldItemsById[itemId] = nil

    ItemBridge.call("update", { itemId, {
        owner_account_id = accountId,
        position = NULL_SENTINEL,
    } }, function(ok, affectedOrError)
        if not ok then
            Logger.error("ItemService", "pickup: failed to update item row", { id = itemId, error = tostring(affectedOrError) })
            return
        end

        if isElement(object) then
            destroyElement(object)
        end

        if not isElement(player) then
            return
        end

        local items = playerItems[player] or {}
        items[#items + 1] = {
            id = itemId,
            schemeKey = entry.item.schemeKey,
            amount = entry.item.amount,
            itemValues = entry.item.itemValues,
            flags = entry.item.flags,
            favorite = entry.item.favorite,
        }
        playerItems[player] = items

        ItemService.sync(player)
        pushItemToast(player, "gained", entry.item.schemeKey, entry.item.amount)
    end)

    return true
end

--- @param player element
-- @param itemId number
ItemService.toggleFavorite = function(player, itemId)
    local item = findOwnItem(player, itemId)
    if not item then
        return
    end
    item.favorite = not item.favorite
    ItemService.sync(player)
end

--- @param object object
-- @return number|nil the items row id this world object was spawned from
ItemService.worldItemIdOf = function(object)
    return worldItemObjects[object]
end

addEventHandler("onPlayerQuit", root, function()
    ItemService.save(source)
    playerItems[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local function loadWorldItems()
        ItemBridge.call("findOwnerless", {}, function(ok, rowsOrError)
            if not ok then
                Logger.error("ItemService", "Failed to load world items", { error = tostring(rowsOrError) })
                return
            end

            local spawned = 0
            for _, row in ipairs(rowsOrError) do
                local scheme = ItemSchemes.get(row.scheme_key)
                local position = row.position
                if scheme and type(position) == "table" then
                    spawnWorldObject(scheme, position[1], position[2], position[3], row.interior, row.dimension, itemFromRow(row))
                    spawned = spawned + 1
                end
            end

            Logger.info("ItemService", "Loaded world items", { count = spawned })
        end)
    end

    -- Same DATABASE_READY/Schema.isMigrated() gotcha documented in
    -- docs/DatabaseContract.md - core (a resource that started earlier in
    -- core_bootstrap's chain) may still be mid-migration when THIS
    -- resource's onResourceStart fires.
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    if migratedOk and migrated then
        loadWorldItems()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, loadWorldItems)
    end

    setTimer(function()
        for player in pairs(playerItems) do
            if isElement(player) then
                ItemService.save(player)
            end
        end
    end, SAVE_INTERVAL_MS, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(playerItems) do
        if isElement(player) then
            ItemService.save(player)
        end
    end
end)
