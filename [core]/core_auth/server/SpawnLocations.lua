-- Deliberately a plain Lua table, not a database table - these are
-- designer-authored, world-fixed locations. `id` is the only field ever
-- sent back by the client to identify a choice, so it must stay stable
-- once players have seen it.

SpawnLocations = {
    {
        x = 2495.0,
        y = -1687.0,
        z = 13.5,
        id = "grove_street",
        name = "Grove Street",
        interior = 0,
        dimension = 0,
        description = "Los Santos - South Central",
    },
    {
        x = 2000.0,
        y = -1780.0,
        z = 13.5,
        id = "idlewood",
        name = "Idlewood",
        interior = 0,
        dimension = 0,
        description = "Los Santos - Idlewood",
    },
    {
        x = 2000.0,
        y = 1544.0,
        z = 10.8,
        id = "las_venturas_strip",
        name = "The Strip",
        interior = 0,
        dimension = 0,
        description = "Las Venturas - kasyna i neony",
    },
    {
        x = -2035.0,
        y = 158.0,
        z = 30.7,
        id = "san_fierro_downtown",
        name = "San Fierro Downtown",
        interior = 0,
        dimension = 0,
        description = "San Fierro - centrum miasta",
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

--- @return table[] array of { id, name, description }
SpawnLocations.toPublicList = function()
    local list = {}
    for i, location in ipairs(SpawnLocations) do
        list[i] = { id = location.id, name = location.name, description = location.description }
    end
    return list
end
