-- Scoreboard (TAB): pressing TAB toggles the player list open/closed (it
-- stays open, no need to hold the key) - movement/camera/shooting keep
-- working while it's open, exactly like gm_voice/gm_radio's HUD elements
-- (see UI.showOverlay's own module comment in BrowserManager.lua:
-- overlays never touch showCursor/guiSetInputEnabled/focusBrowser by
-- design). Right-click, while the scoreboard is open, independently
-- toggles cursor/browser focus (core_ui's uiFocusBrowser export) and
-- movement lock (toggleAllControls, the same primitive gm_blackout
-- already uses independently of core_ui) so the list can actually be
-- clicked/scrolled/searched - press again to give control back. Both are
-- plain toggles, following a proven reference implementation from another
-- project rather than a "hold" model - a "hold tab, ALSO hold
-- right-click" combo turned out to fight with MTA's own bindKey/
-- guiSetInputEnabled interaction (bindKey's held-state tracking got
-- confused once guiSetInputEnabled(true) engaged), so this only listens
-- for right-click via onClientKey (a plain event, not a binding) and only
-- WHILE the scoreboard is open, exactly like the reference's own
-- toggleMouse being added/removed from onClientKey dynamically instead of
-- gating on a flag inside a permanent handler.
ScoreboardState = ScoreboardState or {}

-- While open, the list is re-requested on this interval so joins/quits/
-- status changes (someone finishing login, picking a spawn, etc.) show up
-- without having to close and reopen it.
local REFRESH_INTERVAL_MS = 2000

local scoreboardOpen = false
local cursorActive = false
local refreshTimer = nil

local function requestPlayers()
    triggerServerEvent(Events.SCOREBOARD_REQUEST_PLAYERS, resourceRoot)
end

--- Only bound to onClientKey while scoreboardOpen (see openScoreboard/
--- closeScoreboard) - toggles cursor/focus/movement-lock on every
--- right-click PRESS, ignores the release entirely (matches the
--- reference's own toggleMouse: `if button ~= 'mouse2' or not down then return end`).
local function onRightClick(key, state)
    if key ~= "mouse2" or not state then
        return
    end

    cursorActive = not cursorActive
    toggleAllControls(not cursorActive)
    exports.core_ui:uiFocusBrowser(cursorActive)
end

local function openScoreboard()
    if scoreboardOpen then
        return
    end
    -- Not usable before the local player has actually spawned (still on
    -- the loading/auth/spawn-select screens - see App.tsx's own Switch on
    -- windowState.activeWindow) - the CEF window is fully occupied by
    -- those screens at that point anyway, and there is no gameplay to tab
    -- out of yet.
    if getElementData(localPlayer, ElementData.Player.SPAWNED) ~= true then
        return
    end
    scoreboardOpen = true

    exports.core_ui:uiShowOverlay("scoreboard")
    addEventHandler("onClientKey", root, onRightClick)
    requestPlayers()
    refreshTimer = setTimer(requestPlayers, REFRESH_INTERVAL_MS, 0)
end

local function closeScoreboard()
    if not scoreboardOpen then
        return
    end
    scoreboardOpen = false

    removeEventHandler("onClientKey", root, onRightClick)
    if cursorActive then
        cursorActive = false
        toggleAllControls(true)
        exports.core_ui:uiFocusBrowser(false)
    end

    if isTimer(refreshTimer) then
        killTimer(refreshTimer)
    end
    refreshTimer = nil

    exports.core_ui:uiHideOverlay("scoreboard")
end

local function toggleScoreboard()
    if scoreboardOpen then
        closeScoreboard()
    else
        openScoreboard()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("tab", "down", toggleScoreboard)
end)

addEvent(Events.SCOREBOARD_PLAYERS_RECEIVED, true)
addEventHandler(Events.SCOREBOARD_PLAYERS_RECEIVED, root, function(players)
    exports.core_ui:uiPushEvent(Events.PUSH_SCOREBOARD_PLAYERS, players)
end)

addEventHandler("onClientResourceStop", resourceRoot, closeScoreboard)
