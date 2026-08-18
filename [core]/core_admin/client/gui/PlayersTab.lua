playersList = {}
selectedPlayer = nil

local playersTab
local gridPlayers, columnPlayerLogin, columnPlayerRole, columnPlayerDuty
local labelPlayerInfo
local buttonWarn, buttonMute, buttonKick, buttonBan

function BuildPlayersTab()
    playersTab = guiCreateTab("Gracze", tabPanel)

    gridPlayers = guiCreateGridList(10, 10, 300, 375, false, playersTab)
    columnPlayerLogin = guiGridListAddColumn(gridPlayers, "Login", 0.4)
    columnPlayerRole = guiGridListAddColumn(gridPlayers, "Ranga", 0.35)
    columnPlayerDuty = guiGridListAddColumn(gridPlayers, "Służba administracyjna", 0.2)

    labelPlayerInfo = guiCreateLabel(325, 10, 345, 40, "Wybierz gracza z listy.", false, playersTab)
    guiLabelSetVerticalAlign(labelPlayerInfo, "top")
    guiLabelSetHorizontalAlign(labelPlayerInfo, "left", true)

    buttonWarn = guiCreateButton(325, 60, 80, 28, "Ostrzeż", false, playersTab)
    buttonMute = guiCreateButton(410, 60, 80, 28, "Wycisz", false, playersTab)
    buttonKick = guiCreateButton(325, 95, 80, 28, "Wyrzuć", false, playersTab)
    buttonBan = guiCreateButton(410, 95, 80, 28, "Zbanuj", false, playersTab)

    addEventHandler("onClientGUIClick", resourceRoot, function()
        if source == gridPlayers then
            onPlayersGridClick()
        elseif source == buttonWarn then
            OpenPenaltyDialog("warn")
        elseif source == buttonMute then
            OpenPenaltyDialog("mute")
        elseif source == buttonKick then
            OpenPenaltyDialog("kick")
        elseif source == buttonBan then
            OpenPenaltyDialog("ban")
        end
    end)
end

local function refreshPlayerInfo()
    if not selectedPlayer then
        guiSetText(labelPlayerInfo, "Wybierz gracza z listy.")
        return
    end

    guiSetText(labelPlayerInfo, string.format(
        "Login: %s\nID: %d\nRanga: %s\nSłużba administracyjna: %s",
        selectedPlayer.login,
        selectedPlayer.id,
        ROLE_LABEL[selectedPlayer.role] or tostring(selectedPlayer.role),
        selectedPlayer.onDuty and "Tak" or "Nie"
    ))
end

function onPlayersGridClick()
    local selectedItem = guiGridListGetSelectedItem(gridPlayers)
    if selectedItem == -1 then
        selectedPlayer = nil
    else
        local accountId = guiGridListGetItemData(gridPlayers, selectedItem, columnPlayerLogin)
        for _, entry in ipairs(playersList) do
            if entry.id == accountId then
                selectedPlayer = entry
                break
            end
        end
    end
    refreshPlayerInfo()
end

local function populatePlayersGrid()
    guiGridListClear(gridPlayers)

    for _, entry in ipairs(playersList) do
        local row = guiGridListAddRow(gridPlayers)
        guiGridListSetItemText(gridPlayers, row, columnPlayerLogin, entry.login, false, false)
        guiGridListSetItemText(gridPlayers, row, columnPlayerRole, ROLE_LABEL[entry.role] or tostring(entry.role), false, false)
        guiGridListSetItemText(gridPlayers, row, columnPlayerDuty, entry.onDuty and "Tak" or "Nie", false, false)
        guiGridListSetItemData(gridPlayers, row, columnPlayerLogin, entry.id)
    end
end

function RequestPlayerList()
    triggerServerEvent(Events.ADMIN_REQUEST_PLAYER_LIST, resourceRoot)
end

addEvent(Events.ADMIN_PLAYER_LIST, true)
addEventHandler(Events.ADMIN_PLAYER_LIST, root, function(entries)
    playersList = entries or {}
    populatePlayersGrid()
end)

AdminGuiWindow_onPanelOpen(RequestPlayerList)
