screenW, screenH = guiGetScreenSize()

panelOpen = false

window = nil
tabPanel = nil

ROLE_LABEL = {
    [0] = "Gracz",
    [1] = "Weteran",
    [2] = "Supporter",
    [3] = "Moderator",
    [4] = "Administrator",
    [5] = "RCON",
    [6] = "Zarząd",
}

local setPanelVisible
local onPanelOpenCallbacks = {}
local onPanelCloseCallbacks = {}

local function buildWindow()
    window = guiCreateWindow((screenW - 700) / 2, (screenH - 460) / 2, 700, 460, "Panel Administracyjny", false)
    guiWindowSetSizable(window, false)
    guiSetVisible(window, false)

    tabPanel = guiCreateTabPanel(10, 25, 680, 425, false, window)
end

function AdminGuiWindow_onPanelOpen(callback)
    onPanelOpenCallbacks[#onPanelOpenCallbacks + 1] = callback
end

function AdminGuiWindow_onPanelClose(callback)
    onPanelCloseCallbacks[#onPanelCloseCallbacks + 1] = callback
end

function setPanelVisible(visible)
    panelOpen = visible
    guiSetVisible(window, visible)
    showCursor(visible)
    guiSetInputEnabled(visible)

    if visible then
        guiBringToFront(window)
        for _, callback in ipairs(onPanelOpenCallbacks) do
            callback()
        end
    else
        for _, callback in ipairs(onPanelCloseCallbacks) do
            callback()
        end
    end
end

addEvent(Events.ADMIN_PANEL_TOGGLE, true)
addEventHandler(Events.ADMIN_PANEL_TOGGLE, root, function()
    setPanelVisible(not panelOpen)
end)

addEvent(Events.ADMIN_DUTY_CHANGED, true)
addEventHandler(Events.ADMIN_DUTY_CHANGED, root, function(isOnDuty)
    if not isOnDuty and panelOpen then
        setPanelVisible(false)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    buildWindow()
    BuildPlayersTab()
    BuildReportsTab()
    BuildPenaltyDialog()
end)
