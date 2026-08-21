-- Active Record model for the items table - both a player's carried
-- inventory AND a world-dropped item are the same row, distinguished by
-- owner_account_id being set vs. NULL (see ItemRepository.lua's
-- findOwnerless/findByOwnerAccountId split, same "owner = -1 means it's
-- lying in the world" convention the reference implementation this was
-- ported from used, translated to a real nullable FK here instead of a
-- sentinel value). See docs/DatabaseContract.md's "Items table" section.
--
-- item_values/flags have no first-class place in Schema.lua's column
-- type DSL (no "json" type - see Vehicle.lua's own module comment for
-- the same reasoning) - stored as "text" columns holding toJSON/
-- fromJSON-encoded Lua tables. ItemRepository.lua is the only place that
-- touches the encoding/decoding; callers above it always see real Lua tables.
Item = Model:extend("items", {
    { name = "id", type = "id", primaryKey = true },
    -- NULL = this item is lying in the world (owner-less), not carried -
    -- see this file's own module comment.
    { name = "owner_account_id", type = "reference", nullable = true, references = { table = "accounts", column = "id" } },
    -- ItemSchemes.lua key, e.g. "Mała ryba" - the scheme itself (name,
    -- type, category, weight, stack limit, world object model) lives in
    -- gm_items/shared/ItemSchemes.lua, not the database, so balance
    -- changes don't need a migration.
    { name = "scheme_key", type = "string", length = 64, nullable = false },
    { name = "amount", type = "integer", nullable = false, default = 1 },
    -- Per-instance data the scheme alone can't hold - e.g. a vehicle
    -- key's { vehicleId }. {} for schemes with no extra data.
    { name = "item_values", type = "text", nullable = true },
    -- Per-instance behavior flags (e.g. noDrop) - {} for none.
    { name = "flags", type = "text", nullable = true },
    { name = "favorite", type = "boolean", nullable = false, default = false },
    -- World position { x, y, z } as text/JSON, not separate integer
    -- columns - MTA world coordinates are floats, and there's no
    -- first-class float column type either (see this file's own module
    -- comment on item_values/flags). Only meaningful while
    -- owner_account_id is NULL - see gm_items/server/ItemService.lua's
    -- spawnWorldObject/pickup.
    { name = "position", type = "text", nullable = true },
    { name = "interior", type = "integer", nullable = false, default = 0 },
    { name = "dimension", type = "integer", nullable = false, default = 0 },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "updated_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

Account:hasMany("items", Item, "owner_account_id")
Item:belongsTo("owner", Account, "owner_account_id")
