-- F11 world map: pressing F11 toggles the map open/closed (it stays
-- open, no need to hold the key). Unlike gm_scoreboard's own TAB overlay
-- (movement keeps working, cursor/focus/movement-lock sit behind a
-- separate right-click toggle), this engages cursor/focus/movement-lock
-- immediately on open - it's a full-screen map you look at, not a HUD
-- element you glance at while still playing, so there's no reason to
-- make the player press twice (or keep control of a ped they can't see)
-- to actually use it. See UI.showOverlay's own module comment in
-- BrowserManager.lua: overlays never touch showCursor/guiSetInputEnabled/
-- focusBrowser by design, so this handles all three itself, same as
-- gm_scoreboard/gm_items do once their own cursor mode engages.
WorldMapState = WorldMapState or {}

-- While open, the snapshot is re-requested on this interval so players
-- moving around / joining / quitting show up without closing and
-- reopening the map. Slower than the scoreboard's own 2000ms - a moving
-- blip doesn't need to be as fresh as a player status list.
local REFRESH_INTERVAL_MS = 3000

local mapOpen = false
local refreshTimer = nil

local function requestData()
    triggerServerEvent(Events.WORLDMAP_REQUEST_DATA, resourceRoot)
end

local function openMap()
    if mapOpen then
        return
    end
    mapOpen = true

    exports.ui_hud:setHUDVisible(false)
    exports.core_ui:uiShowOverlay("worldMap")
    exports.core_ui:uiFocusBrowser(true)
    toggleAllControls(false)
    showCursor(true)
    showChat(false)

    requestData()
    refreshTimer = setTimer(requestData, REFRESH_INTERVAL_MS, 0)
end

local function closeMap()
    if not mapOpen then
        return
    end
    mapOpen = false

    if isTimer(refreshTimer) then
        killTimer(refreshTimer)
    end
    refreshTimer = nil

    exports.ui_hud:setHUDVisible(true)
    exports.core_ui:uiFocusBrowser(false)
    exports.core_ui:uiHideOverlay("worldMap")
    toggleAllControls(true)
    showCursor(false)
    showChat(true)
end

local function toggleMap()
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end

    if mapOpen then
        closeMap()
    else
        openMap()
    end

    cancelEvent()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    toggleControl("radar", false)
    addEventHandler("onClientKey", root, function(key, state)
        if key == "F11" and state then
            toggleMap()
        end
    end)
end)

addEvent(Events.WORLDMAP_DATA_RECEIVED, true)
addEventHandler(Events.WORLDMAP_DATA_RECEIVED, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_WORLDMAP_DATA, data)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeMap()
end)
