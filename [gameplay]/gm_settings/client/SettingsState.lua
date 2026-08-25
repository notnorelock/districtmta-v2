-- Applies each real toggle effect (SETTINGS_APPLY from the server) and
-- relays the CEF panel's own toggle clicks to the server - mirrors
-- gm_items/client/InventoryState.lua's own "server owns state, this file
-- only relays + applies local effects" split. Panel open/close
-- (F10/cursor lifecycle) moved to ui_dashboard/client/DashboardState.lua -
-- this file no longer touches the "dashboard" overlay at all.
SettingsState = SettingsState or {}

-- The CLIENT-side half of the registry concept - server/SettingsRegistry.lua
-- owns the whitelist of valid ids, this owns what actually HAPPENS
-- locally when one flips. Adding toggle #2 later: one new key here
-- calling whatever future system's own export - no other code in this
-- file changes.
local EFFECTS = {
    -- setHUDUserPreference, NOT setHUDVisible - this is a STANDING
    -- player preference, not a temporary show/hide like F11's world map
    -- or gm_blackout use. ui_hud's own HUDState.lua treats this
    -- separately so a later "temporary" setHUDVisible(true) call from
    -- one of those (e.g. closing the world map) can't silently override
    -- the player's own choice to keep the HUD hidden - see that file's
    -- own userPreferenceHidden comment.
    hud_disabled = function(enabled)
        exports.ui_hud:setHUDUserPreference(enabled)
    end,
}

-- Remembers the last enabled/disabled state applied for each toggle id -
-- lets settingsStateIsEnabled (below) answer synchronously for a
-- resource that starts/restarts AFTER this one already has a fresh
-- value (e.g. ui_hud restarted on its own, without gm_settings itself
-- restarting - its own local state, like HUDState.lua's own
-- userPreferenceHidden, would otherwise reset to its default and lose
-- track of the player's actual choice until the next real toggle).
local lastEnabled = {}

addEvent(Events.SETTINGS_APPLY, true)
addEventHandler(Events.SETTINGS_APPLY, root, function(data)
    if type(data) ~= "table" or type(data.id) ~= "string" then
        return
    end
    local enabled = data.enabled == true
    lastEnabled[data.id] = enabled
    local effect = EFFECTS[data.id]
    if effect then
        effect(enabled)
    end
end)

--- Synchronous read of a toggle's last-known enabled state, for a
--- resource that needs to restore it on its OWN startup rather than
--- waiting for the next SETTINGS_APPLY push (which only fires on login
--- or an actual toggle, neither of which happens on a lone resource
--- restart). See ui_hud/client/HUDState.lua's own onClientResourceStart
--- handler for the caller.
-- @param id string
-- @return boolean false if never applied yet (e.g. gm_settings itself
--         hasn't received its own PLAYER_ACCOUNT_RESOLVED resync yet)
function settingsStateIsEnabled(id)
    return lastEnabled[id] == true
end

addEvent(Events.SETTINGS_SYNCED, true)
addEventHandler(Events.SETTINGS_SYNCED, root, function(enabledIds)
    exports.core_ui:uiPushEvent(Events.PUSH_SETTINGS_SYNCED, enabledIds or {})
end)

-- CEF -> client Lua (via mta.notify) -> server: player flipped one
-- checkbox in the panel. Server re-validates the id and enabled type
-- itself (never trusts the panel) - see server/SettingsService.lua's own
-- SETTINGS_TOGGLE handler. Since a settings toggle is a pure player
-- preference with no gameplay-fairness stake (unlike e.g. exam grading,
-- which never trusts the client for anything that matters), the server
-- can reasonably trust the id/enabled VALUES themselves once validated
-- against the whitelist - there's no "cheating" a HUD visibility toggle.
addEvent(Events.SETTINGS_TOGGLE, true)
addEventHandler(Events.SETTINGS_TOGGLE, root, function(id, enabled)
    triggerServerEvent(Events.SETTINGS_TOGGLE, resourceRoot, id, enabled)
end)
