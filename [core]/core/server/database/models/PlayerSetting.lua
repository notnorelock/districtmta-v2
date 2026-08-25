-- Active Record model for the player_settings table - one row per
-- account, holding the player's enabled setting-toggle ids
-- (gm_settings/server/SettingsRegistry.lua keys) as a JSON-encoded
-- array. "enabled" has no first-class place in Schema.lua's column type
-- DSL (no "json" type - see Item.lua's own module comment for the same
-- reasoning) - stored as a "text" column holding a toJSON/fromJSON-
-- encoded Lua array. SettingsRepository.lua is the only place that
-- touches the encoding/decoding; callers above it always see a real Lua
-- array. Created lazily on first toggle, not at account-creation time.
PlayerSetting = Model:extend("player_settings", {
    { name = "id", type = "id", primaryKey = true },
    { name = "account_id", type = "reference", nullable = false, unique = true, references = { table = "accounts", column = "id" } },
    { name = "enabled", type = "text", nullable = false },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
    { name = "updated_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

PlayerSetting:belongsTo("account", Account, "account_id")
