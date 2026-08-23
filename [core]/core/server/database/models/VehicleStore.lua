-- Active Record model for the vehicle_stores table - configured vehicle
-- storage lot locations (an admin-managed set of "garages" a private
-- vehicle can be stored into/retrieved from, see gm_vehicles/server/
-- VehicleStorageService.lua). enter_position/spawn_positions are "text"
-- columns holding toJSON/fromJSON-encoded Lua tables, same convention
-- Vehicle.lua's own JSON columns use - VehicleStoreRepository.lua is the
-- only place that touches the encoding/decoding.
VehicleStore = Model:extend("vehicle_stores", {
    { name = "id", type = "id", primaryKey = true },
    { name = "name", type = "string", length = 64, nullable = false },
    -- Enums.VehicleStorePurpose - PRIVATE (default, existing behavior: any
    -- owner's private vehicles, gm_vehicles/server/VehicleStorageService.lua's
    -- own owned-or-has-key filter) or GROUP (dedicated to one group's own
    -- vehicles, group_id below - filtered by group membership + rank
    -- allowlist + duty-if-fraction instead).
    { name = "purpose", type = "enum", values = { "private", "group" }, nullable = false, default = "private" },
    -- Non-nil only for a GROUP-purpose lot.
    { name = "group_id", type = "reference", nullable = true, references = { table = "groups", column = "id" } },
    -- { x, y, z } - marker a player walks into to open the retrieval
    -- panel (see gm_vehicles/server/VehicleStorageService.lua). Storing a
    -- vehicle is a SEPARATE marker (store_position, below) - the two used
    -- to be the same spot; kept apart now so a driver dropping a car off
    -- never has to fight the panel's own right-click cursor toggle just
    -- to press G.
    { name = "enter_position", type = "text", nullable = false },
    -- { x, y, z } - drive a vehicle onto this marker's colshape and press
    -- G to store it (owner-only, PRIVATE purpose only - unchanged
    -- validation, see VehicleStorageService.lua's onStoreZoneHit).
    -- Nullable - an older row created before this column existed simply
    -- has no store marker until an admin sets one via /setstorepos.
    { name = "store_position", type = "text", nullable = true },
    -- Array of { x, y, z, rx, ry, rz } - one retrieved vehicle is placed
    -- at the first free-feeling entry from this list (checked in order,
    -- retrieval fails if every one is currently occupied by another
    -- vehicle - see VehicleStorageService.lua's own retrieve handler).
    { name = "spawn_positions", type = "text", nullable = false },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

-- Mirrors Vehicle.lua's own Account:hasMany("vehicles", ...)/
-- Vehicle:belongsTo("owner", ...) pair - vehicle:store(callback) fetches
-- the lot a stored vehicle belongs to (nil store_id resolves to no row,
-- same as belongsTo always does for a nullable foreign key), store:
-- vehicles(callback) fetches every vehicle (any owner) currently sitting
-- in that lot - see AdminCommands.lua's "/removestore" for the one
-- existing caller of the latter (VehicleRepository.findByStoreId does the
-- same query directly rather than through this relation, since it needs
-- JSON-column decoding VehicleRepository owns - this relation exists for
-- completeness/future callers, not because something requires it today).
VehicleStore:hasMany("vehicles", Vehicle, "store_id")
Vehicle:belongsTo("store", VehicleStore, "store_id")
