-- F11 world map: builds the current snapshot (online players + static
-- points of interest) on request. Request/response rather than a
-- periodic broadcast (see Events.lua's own comment on
-- WORLDMAP_REQUEST_DATA) - same reasoning as gm_scoreboard's own
-- ScoreboardService.lua, no point pushing to players who don't have the
-- map open.
WorldMapService = WorldMapService or {}

--- @param player element
-- @return table|nil plain-data entry, or nil if the player has no
--         position worth showing yet (not spawned into the world)
local function toPlayerEntry(player)
    if getElementData(player, ElementData.Player.SPAWNED) ~= true then
        return nil
    end

    local x, y, z = getElementPosition(player)
    local interior = getElementInterior(player)
    local dimension = getElementDimension(player)

    return {
        id = getElementData(player, ElementData.Player.ID) or 0,
        name = getPlayerName(player),
        x = x,
        y = y,
        z = z,
        interior = interior,
        dimension = dimension,
    }
end

--- @return table[] one entry per spawned player currently in the default
--         interior/dimension - an interior/dimension-0 player elsewhere
--         wouldn't plot meaningfully onto the one flat overworld map, so
--         they're simply omitted rather than mis-plotted at their raw x/y.
local function getPlayerEntries()
    local entries = {}
    for _, player in ipairs(getElementsByType("player")) do
        local entry = toPlayerEntry(player)
        if entry and entry.interior == 0 and entry.dimension == 0 then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

--- @param store table a VehicleStoreRepository row (enter_position already decoded)
-- @return table plain-data entry - only what the map needs to plot a pin,
--         not the store's own spawn_positions/created_at internals
local function toStoreEntry(store)
    local position = store.enter_position or {}
    return {
        id = store.id,
        name = store.name,
        x = position.x or 0,
        y = position.y or 0,
    }
end

addEvent(Events.WORLDMAP_REQUEST_DATA, true)
addEventHandler(Events.WORLDMAP_REQUEST_DATA, root, function()
    -- Server-authoritative mirror of WorldMapState.lua's own spawned
    -- check - see ScoreboardService.lua's own identical comment on why
    -- (a modified client could send this without the client-side gate).
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end

    local requestingClient = client

    VehicleStoreBridge.findAll(function(ok, stores)
        local storeEntries = {}
        if ok and type(stores) == "table" then
            for _, store in ipairs(stores) do
                storeEntries[#storeEntries + 1] = toStoreEntry(store)
            end
        end

        if not isElement(requestingClient) then
            return
        end

        triggerClientEvent(requestingClient, Events.WORLDMAP_DATA_RECEIVED, requestingClient, {
            players = getPlayerEntries(),
            stores = storeEntries,
        })
    end)
end)
