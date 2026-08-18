reportsList = {}
reportsOverlayOpen = false

local reportsTab
local gridReports, columnReportTarget, columnReportReporter, columnReportReason, columnReportDate
local buttonResolveReport, labelReportsCount
local selectedReportId = nil

function BuildReportsTab()
    reportsTab = guiCreateTab("Zgłoszenia", tabPanel)

    gridReports = guiCreateGridList(10, 10, 660, 335, false, reportsTab)
    columnReportTarget = guiGridListAddColumn(gridReports, "Zgłoszony", 0.2)
    columnReportReporter = guiGridListAddColumn(gridReports, "Zgłaszający", 0.2)
    columnReportReason = guiGridListAddColumn(gridReports, "Powód", 0.4)
    columnReportDate = guiGridListAddColumn(gridReports, "Data", 0.2)

    buttonResolveReport = guiCreateButton(10, 355, 150, 28, "Rozwiąż", false, reportsTab)
    guiSetProperty(buttonResolveReport, "Disabled", "True")
    labelReportsCount = guiCreateLabel(500, 360, 170, 20, "Otwartych zgłoszeń: 0", false, reportsTab)

    addEventHandler("onClientGUIClick", resourceRoot, function()
        if source == gridReports then
            onReportsGridClick()
        elseif source == buttonResolveReport then
            if selectedReportId then
                triggerServerEvent(Events.ADMIN_RESOLVE_REPORT, resourceRoot, selectedReportId)
            end
        end
    end)
end

local function populateReportsGrid()
    guiGridListClear(gridReports)

    for _, report in ipairs(reportsList) do
        local row = guiGridListAddRow(gridReports)
        guiGridListSetItemText(gridReports, row, columnReportTarget, report.reportedLogin or ("#" .. tostring(report.reportedAccountId)), false, false)
        guiGridListSetItemText(gridReports, row, columnReportReporter, report.reporterLogin or ("#" .. tostring(report.reporterAccountId)), false, false)
        guiGridListSetItemText(gridReports, row, columnReportReason, report.reason, false, false)
        guiGridListSetItemText(gridReports, row, columnReportDate, report.createdAt, false, false)
        guiGridListSetItemData(gridReports, row, columnReportTarget, report.id)
    end

    guiSetText(labelReportsCount, "Otwartych zgłoszeń: " .. #reportsList)
    guiSetProperty(buttonResolveReport, "Disabled", "True")
    selectedReportId = nil
end

function onReportsGridClick()
    local selectedItem = guiGridListGetSelectedItem(gridReports)
    if selectedItem == -1 then
        selectedReportId = nil
        guiSetProperty(buttonResolveReport, "Disabled", "True")
    else
        selectedReportId = guiGridListGetItemData(gridReports, selectedItem, columnReportTarget)
        guiSetProperty(buttonResolveReport, "Disabled", "False")
    end
end

function RequestReportList()
    triggerServerEvent(Events.ADMIN_REQUEST_REPORT_LIST, resourceRoot)
end

addEvent(Events.ADMIN_REPORT_LIST, true)
addEventHandler(Events.ADMIN_REPORT_LIST, root, function(reports)
    reportsList = reports or {}
    populateReportsGrid()
end)

addEvent(Events.ADMIN_REPORT_CREATED_NOTICE, true)
addEventHandler(Events.ADMIN_REPORT_CREATED_NOTICE, root, function(report)
    outputChatBox("[Admin] Nowe zgłoszenie na konto #" .. tostring(report.reportedAccountId) .. ".", 255, 111, 0)

    if panelOpen or reportsOverlayOpen then
        RequestReportList()
    end
end)

AdminGuiWindow_onPanelOpen(RequestReportList)

--------------------------------------------------------------------------
-- Reports overlay
--------------------------------------------------------------------------

addEvent(Events.REPORTS_OVERLAY_TOGGLE, true)
addEventHandler(Events.REPORTS_OVERLAY_TOGGLE, root, function()
    reportsOverlayOpen = not reportsOverlayOpen
    if reportsOverlayOpen then
        RequestReportList()
    end
end)

addEvent(Events.ADMIN_DUTY_CHANGED, true)
addEventHandler(Events.ADMIN_DUTY_CHANGED, root, function(isOnDuty)
    if not isOnDuty then
        reportsOverlayOpen = false
    end
end)

local REPORTS_OVERLAY_MAX_LINES = 20
local REPORTS_OVERLAY_LINE_HEIGHT = 15

local function reportOverlayLine(report)
    local reportedLabel = report.reportedLogin or ("#" .. tostring(report.reportedAccountId))
    local reporterLabel = report.reporterLogin or ("#" .. tostring(report.reporterAccountId))

    if report.status == Enums.ReportStatus.RESOLVED then
        local resolvedByLabel = report.resolvedByLogin or (report.resolvedByAccountId and ("#" .. tostring(report.resolvedByAccountId))) or "?"
        return ("Przyjęty przez %s | (%s) %s -> %s: %s"):format(
            resolvedByLabel, tostring(report.createdAt), reporterLabel, reportedLabel, tostring(report.reason)
        ), tocolor(0, 255, 0, 255)
    end

    return ("#c6b6b6(%s) #2ecc71%s#c6b6b6 -> #e74c3c%s#c6b6b6: #ffffff%s"):format(
        tostring(report.createdAt), reporterLabel, reportedLabel, tostring(report.reason)
    ), tocolor(255, 255, 255, 255)
end

addEventHandler("onClientRender", root, function()
    if not reportsOverlayOpen then
        return
    end

    local x, y, width = 0, screenH / 2 - 200, screenW - 25
    local count = #reportsList
    local counterColor = count > REPORTS_OVERLAY_MAX_LINES and tocolor(255, 0, 0, 255) or tocolor(0, 255, 0, 255)

    local title = "Lista raportów (" .. count .. ")"
    dxDrawText(title, x + 1, y - 19, x + width + 1, y, tocolor(0, 0, 0, 255), 1, "default-bold", "right")
    dxDrawText(title, x, y - 20, x + width, y, counterColor, 1, "default-bold", "right")

    local firstIndex = count > REPORTS_OVERLAY_MAX_LINES and (count - REPORTS_OVERLAY_MAX_LINES + 1) or 1
    local offset = 0
    for i = firstIndex, count do
        local report = reportsList[i]
        local line, color = reportOverlayLine(report)

        dxDrawText(line, x + 1, y + offset + 1, x + width + 1, 0, tocolor(0, 0, 0, 255), 1, "default-bold", "right", "top", false, false, false, true)
        dxDrawText(line, x, y + offset, x + width, 0, color, 1, "default-bold", "right", "top", false, false, false, true)

        offset = offset + REPORTS_OVERLAY_LINE_HEIGHT
    end
end)
