-- Active Record model for the vehicles table - persistent PRIVATE
-- vehicles only (Enums.VehiclePurpose.PUBLIC is a purely scripted/
-- runtime concept, never written here - see gm_vehicles/server/
-- PublicVehicles.lua). See docs/DatabaseContract.md's "Vehicles table"
-- section for the full column reference.
--
-- Complex per-vehicle state (tuning parts/neons/paintjob/engine, door/
-- light/panel/wheel condition, the two-color-per-slot paint, last
-- drivers) has no first-class place in Schema.lua's column type DSL (no
-- "json" type - see Schema.lua's columnSql) - stored as "text" columns
-- holding toJSON/fromJSON-encoded Lua tables, exactly like the reference
-- implementation this was ported from did against its own raw MySQL
-- layer. VehicleRepository.lua is the only place that touches the
-- encoding/decoding; callers above it always see real Lua tables.
Vehicle = Model:extend("vehicles", {
    { name = "id", type = "id", primaryKey = true },
    { name = "purpose", type = "enum", values = { Enums.VehiclePurpose.PRIVATE }, nullable = false },
    { name = "model", type = "integer", nullable = false },
    { name = "position", type = "text", nullable = false },
    { name = "rotation", type = "text", nullable = false },
    { name = "health", type = "integer", nullable = false, default = 1000 },
    { name = "mileage", type = "integer", nullable = false, default = 0 },
    { name = "fuel", type = "integer", nullable = false, default = 100 },
    { name = "max_fuel", type = "integer", nullable = false, default = 100 },
    { name = "owner_account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    -- Non-nil = this vehicle is sitting in a storage lot (vehicle_stores
    -- row), NOT spawned in the world - see gm_vehicles/server/
    -- VehicleStorageService.lua. VehicleService.lua's own onResourceStart
    -- spawn-all-private loader skips any row with a non-nil store_id.
    { name = "store_id", type = "reference", nullable = true, references = { table = "vehicle_stores", column = "id" } },
    { name = "locked", type = "boolean", nullable = false, default = true },
    -- Manual handbrake (setElementFrozen), toggled via gm_vehicles_
    -- interaction's radial menu - see VehicleInteractionService.lua's own
    -- module comment on why setElementFrozen models this (fully immobile,
    -- not just GTA's own space-bar handbrake). Survives save/respawn like
    -- every other transient toggle here (locked, lights, ...).
    { name = "handbrake", type = "boolean", nullable = false, default = false },
    -- { parts, neons, paintjob, engine } - see Enums.lua's own module comment.
    { name = "upgrades", type = "text", nullable = true },
    -- door index (0-5) -> state
    { name = "doors", type = "text", nullable = true },
    -- { state = { [0..3] -> state }, color = { r, g, b } }
    { name = "lights", type = "text", nullable = true },
    -- panel index (0-6) -> state
    { name = "panels", type = "text", nullable = true },
    -- { front-left, front-right, rear-left, rear-right } wheel states
    { name = "wheels", type = "text", nullable = true },
    -- 4 paint slots x {r,g,b} = 12 values, matches getVehicleColor(vehicle, true)
    { name = "color", type = "text", nullable = true },
    { name = "plate", type = "string", length = 8, nullable = true },
    { name = "interior", type = "integer", nullable = false, default = 0 },
    { name = "dimension", type = "integer", nullable = false, default = 0 },
    -- array of { name = "..." }, most recent last - see VehicleService.lua
    { name = "last_drivers", type = "text", nullable = true },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "updated_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("vehicles", Vehicle, "owner_account_id")
Vehicle:belongsTo("owner", Account, "owner_account_id")
