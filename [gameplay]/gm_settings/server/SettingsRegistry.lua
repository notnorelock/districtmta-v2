-- Resource-local registry of every settings toggle this project
-- actually has an implementation for - deliberately NOT in Enums.lua
-- (a toggle id is only ever read by gm_settings itself and its own CEF
-- panel, unlike a value like Enums.LicenseCategory which is both a SQL
-- ENUM column value AND a cross-resource ElementData contract - see
-- LicenseCategories.lua's own module comment for the same "resource-local
-- config, not Enums.lua" precedent this mirrors).
--
-- This is the server-side half of the reference pd_* script's own flat
-- idToEvent table, re-expressed as the whitelist of ids SETTINGS_TOGGLE
-- will accept. The CEF-side label list is a separate, parallel array in
-- packages/ui/src/features/settings/settingsRegistry.ts (not shared/
-- codegen'd - matches how every other push payload in this project is
-- independently typed on each side).
--
-- Adding toggle #2 later: one entry here (id + defaultEnabled) + one
-- entry in settingsRegistry.ts (id + labelKey) + one EFFECTS branch in
-- client/SettingsState.lua - no other code changes anywhere.
SettingsRegistry = {
    -- defaultEnabled is the default state on first-ever login (no
    -- player_settings row yet) - HUD visible by default, so
    -- hud_disabled is NOT in a new account's enabled set. Named for the
    -- ACTION the id enables ("hide the HUD"), not a raw feature on/off,
    -- since that reads more naturally as the checkbox label "Ukryj HUD"
    -- than a double-negative "hud_visible = false" would.
    hud_disabled = {
        defaultEnabled = false,
    },
}

--- @param id any
-- @return boolean true only if id is a known SettingsRegistry key
function settingsRegistryIsValidId(id)
    return type(id) == "string" and SettingsRegistry[id] ~= nil
end
