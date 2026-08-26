-- F10 player-dashboard panel open/close - real blocking UiWindow (same
-- mechanism core_auth's AuthUiClient.lua uses for the login/spawn-select
-- screens), NOT the old additive-overlay + manual right-click cursor
-- toggle. core_ui/client/ui/BrowserManager.lua's UI.open/UI.close already
-- handles cursor/GUI-input/weapon-fire-and-switch lock and browser focus
-- automatically for any blocking window (see updateInputState() there) -
-- this file owns nothing but the F10 keybind and panel open/closed state.
-- Movement (WASD etc.) is deliberately left unlocked, matching how
-- updateInputState() already treats the auth/spawn-select windows.
--
-- F10 is unused by any other resource in this project; no ESC/pause menu
-- exists yet to hook a "Ustawienia" entry into instead.
--
-- This resource owns ONLY panel lifecycle. The Settings tab's actual
-- toggle logic (whitelist/persistence/effects) stays in gm_settings -
-- see gm_settings/client/SettingsState.lua's own module comment. The CEF
-- panel's "settings:toggle" notify (settings.store.ts) reaches
-- gm_settings's own relay via core_ui's shared, resource-agnostic
-- Events.UI_NOTIFY -> triggerEvent(...) mechanism regardless of which
-- resource opened the panel - see core_ui/client/ui/Transport.lua's own
-- UI_NOTIFY handler. No cross-resource wiring is needed here.
DashboardState = DashboardState or {}

local panelOpen = false

local function openPanel()
    if panelOpen then
        return
    end
    panelOpen = true

    showChat(false)
    exports.ui_hud:setHUDVisible(false)
    UI.open(Enums.UiWindow.DASHBOARD)
end

local function closePanel()
    if not panelOpen then
        return
    end
    panelOpen = false

    showChat(true)
    exports.ui_hud:setHUDVisible(true)
    UI.close(Enums.UiWindow.DASHBOARD)
end

local function togglePanel()
    if not exports.core_shared:canPlayerInteract(nil, { requiresSpawned = true, inVehicle = false, whileBlackout = false }) then
        return
    end
    if panelOpen then
        closePanel()
    else
        openPanel()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("F10", "down", togglePanel)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if panelOpen then
        closePanel()
    end
end)
