-- Deliberately a plain Lua table, not a database table - these are
-- designer-authored, world-fixed locations. `id` is the only field ever
-- sent back by the client to identify a choice, so it must stay stable
-- once players have seen it.

SpawnLocations = {
    {
        x=1692.58,y=1456.73,z=10.76,
        id = "lv_lot",
        name = "Las Venturas",
        interior = 0,
        dimension = 0,
        description = "Spawn LV",
    },
}

local locationsById = {}
for _, location in ipairs(SpawnLocations) do
    locationsById[location.id] = location
end

--- @param id string
-- @return table|nil the matching spawn location entry, or nil if unknown
SpawnLocations.findById = function(id)
    return locationsById[id]
end

--- @return table[] array of { id, name, description, x, y } - x/y are
-- the same world coordinates used to actually spawn the player (see
-- gm_roleplay's gameplayEnterWorld), sent to the client purely to place
-- a pin on Map2D.
SpawnLocations.toPublicList = function()
    local list = {}
    for i, location in ipairs(SpawnLocations) do
        list[i] = { id = location.id, name = location.name, description = location.description, x = location.x, y = location.y }
    end
    return list
end
