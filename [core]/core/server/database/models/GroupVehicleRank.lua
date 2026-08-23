-- Active Record model for the group_vehicle_ranks table - a join table:
-- which of a group's ranks may use a given group-owned vehicle (Vehicle
-- rows with purpose = GROUP). No JSON columns. A vehicle with zero rows
-- here has no allowlist yet - see GroupCache.lua's own vehicleRankAllowlist
-- comment on how gm_groups treats that (currently: nobody can use it until
-- a manage_ranks/leader member explicitly sets one via the CEF panel).
GroupVehicleRank = Model:extend("group_vehicle_ranks", {
    { name = "id", type = "id", primaryKey = true },
    { name = "vehicle_id", type = "reference", nullable = false, references = { table = "vehicles", column = "id" } },
    { name = "rank_id", type = "reference", nullable = false, references = { table = "group_ranks", column = "id" } },
})

GroupVehicleRank:belongsTo("vehicle", Vehicle, "vehicle_id")
GroupVehicleRank:belongsTo("rank", GroupRank, "rank_id")
