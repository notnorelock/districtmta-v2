local penaltyWindow, penaltyLabel, penaltyReasonEdit, penaltyDurationEdit, penaltyOkButton, penaltyCancelButton
local reasonHintLabel, durationHintLabel
local pendingPenaltyType = nil

local PENALTY_LABEL = {
    warn = "Ostrzeżenie",
    mute = "Wyciszenie",
    kick = "Wyrzucenie",
    ban = "Ban",
}

function BuildPenaltyDialog()
    penaltyWindow = guiCreateWindow((screenW - 380) / 2, (screenH - 200) / 2, 380, 200, "Wystaw karę", false)
    guiWindowSetSizable(penaltyWindow, false)
    guiSetVisible(penaltyWindow, false)

    penaltyLabel = guiCreateLabel(16, 26, 348, 20, "", false, penaltyWindow)

    reasonHintLabel = guiCreateLabel(16, 50, 348, 14, "Powód:", false, penaltyWindow)
    guiSetFont(reasonHintLabel, "default-small")
    penaltyReasonEdit = guiCreateEdit(16, 66, 348, 26, "", false, penaltyWindow)

    durationHintLabel = guiCreateLabel(16, 98, 348, 14, "Czas trwania w minutach (puste = na stałe):", false, penaltyWindow)
    guiSetFont(durationHintLabel, "default-small")
    penaltyDurationEdit = guiCreateEdit(16, 114, 348, 26, "", false, penaltyWindow)

    penaltyOkButton = guiCreateButton(16, 152, 168, 28, "Zatwierdź", false, penaltyWindow)
    penaltyCancelButton = guiCreateButton(196, 152, 168, 28, "Anuluj", false, penaltyWindow)

    addEventHandler("onClientGUIClick", resourceRoot, function()
        if source == penaltyCancelButton then
            ClosePenaltyDialog()
        elseif source == penaltyOkButton then
            onPenaltyOkClick()
        end
    end)
end

function OpenPenaltyDialog(penaltyType)
    if not selectedPlayer then
        return
    end

    pendingPenaltyType = penaltyType
    guiSetText(penaltyLabel, (PENALTY_LABEL[penaltyType] or penaltyType) .. " - " .. selectedPlayer.login)
    guiSetText(penaltyReasonEdit, "")
    guiSetText(penaltyDurationEdit, "")

    local durationApplies = penaltyType == "mute" or penaltyType == "ban"
    guiSetProperty(penaltyDurationEdit, "ReadOnly", durationApplies and "False" or "True")

    guiSetVisible(penaltyWindow, true)
    guiBringToFront(penaltyWindow)
end

function ClosePenaltyDialog()
    guiSetVisible(penaltyWindow, false)
    pendingPenaltyType = nil
end

addEvent(Events.ADMIN_ISSUE_PENALTY, true)

function onPenaltyOkClick()
    if not selectedPlayer or not pendingPenaltyType then
        ClosePenaltyDialog()
        return
    end

    local reason = guiGetText(penaltyReasonEdit)
    if reason == "" then
        reason = nil
    end

    local durationMinutes = tonumber(guiGetText(penaltyDurationEdit))
    local durationSeconds = durationMinutes and durationMinutes > 0 and math.floor(durationMinutes * 60) or nil

    triggerServerEvent(Events.ADMIN_ISSUE_PENALTY, resourceRoot, {
        type = pendingPenaltyType,
        targetAccountId = selectedPlayer.id,
        reason = reason,
        durationSeconds = durationSeconds,
    })

    ClosePenaltyDialog()
end

AdminGuiWindow_onPanelClose(ClosePenaltyDialog)
