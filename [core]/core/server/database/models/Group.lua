-- Active Record model for the groups table (factions/gangs/organizations) -
-- see gm_groups/server/GroupDutyService.lua for the duty-marker/skin-swap
-- logic that actually consumes duty_position, and GroupRepository.lua for
-- the JSON encode/decode boundary that field needs.
Group = Model:extend("groups", {
    { name = "id", type = "id", primaryKey = true },
    { name = "name", type = "string", length = 64, nullable = false, unique = true },
    { name = "type", type = "enum", values = { "gang", "organization", "fraction" }, nullable = false },
    -- "#RRGGBB" cosmetic override for the duty marker/HUD color - falls
    -- back to a type-based default (red/blue/gold) client-side when nil.
    { name = "color", type = "string", length = 7, nullable = true },
    { name = "leader_account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    -- { x, y, z, interior, dimension } JSON - nil means no duty marker has
    -- been placed yet (group exists but isn't "live" for duty purposes).
    { name = "duty_position", type = "text", nullable = true },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

-- hasMany("ranks")/hasMany("members") are declared in GroupRank.lua/
-- GroupMember.lua instead (the child tables' own model files, loaded
-- after this one) - same convention VehicleStore.lua uses for its own
-- VehicleStore:hasMany("vehicles", ...)/Vehicle:belongsTo("store", ...)
-- pair, since a relation naming a not-yet-loaded model can't be declared
-- here without reordering the whole load chain.
Group:belongsTo("leader", Account, "leader_account_id")
Account:hasMany("ledGroups", Group, "leader_account_id")

-- Vehicle.lua loads BEFORE this file (see core/meta.xml), so this
-- direction of the relation is safe to declare here - the reverse
-- (Vehicle:belongsTo("group", ...)) would reference a not-yet-loaded
-- Group at Vehicle.lua's own load time, same reasoning as the
-- ranks/members pair above.
Group:hasMany("vehicles", Vehicle, "group_id")
Vehicle:belongsTo("group", Group, "group_id")
