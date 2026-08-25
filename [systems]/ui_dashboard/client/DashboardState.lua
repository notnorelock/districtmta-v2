-- F10 player-dashboard panel open/close - plain toggle, non-blocking
-- overlay that only engages cursor/focus/movement-lock on a separate
-- right-click toggle while open - exact gm_items/client/InventoryState.lua
-- pattern. F10 is unused by any other resource in this project; no
-- ESC/pause menu exists yet to hook a "Ustawienia" entry into instead.
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
local cursorActive = false

local function onRightClick(key, state)
    if key ~= "mouse2" or not state then
        return
    end
    cursorActive = not cursorActive
    toggleAllControls(not cursorActive)
    exports.core_ui:uiFocusBrowser(cursorActive)
end

local function openPanel()
    if panelOpen then
        return
    end
    panelOpen = true

    exports.core_ui:uiShowOverlay("dashboard")
    addEventHandler("onClientKey", root, onRightClick)
end

local function closePanel()
    if not panelOpen then
        return
    end
    panelOpen = false

    removeEventHandler("onClientKey", root, onRightClick)
    if cursorActive then
        cursorActive = false
        toggleAllControls(true)
        exports.core_ui:uiFocusBrowser(false)
    end

    exports.core_ui:uiHideOverlay("dashboard")
end

local function togglePanel()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
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
