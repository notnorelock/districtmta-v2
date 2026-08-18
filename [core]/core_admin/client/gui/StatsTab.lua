statsList = {}

local statsTab
local gridStats, columnStatsLogin, columnStatsRole, columnStatsDuty, columnStatsSessions, columnStatsPenalties, columnStatsReports
local statsTabBuilt = false

local function buildStatsTabIfPermitted()
    if statsTabBuilt then
        return
    end
    statsTabBuilt = true

    statsTab = guiCreateTab("Statystyki", tabPanel)

    gridStats = guiCreateGridList(10, 10, 660, 375, false, statsTab)
    columnStatsLogin = guiGridListAddColumn(gridStats, "Login", 0.2)
    columnStatsRole = guiGridListAddColumn(gridStats, "Ranga", 0.16)
    columnStatsDuty = guiGridListAddColumn(gridStats, "Czas na służbie", 0.2)
    columnStatsSessions = guiGridListAddColumn(gridStats, "Sesje", 0.12)
    columnStatsPenalties = guiGridListAddColumn(gridStats, "Kary", 0.14)
    columnStatsReports = guiGridListAddColumn(gridStats, "Rozw. zgłoszenia", 0.18)

    RequestStats()
end

addEvent(Events.ADMIN_PERMISSIONS, true)
addEventHandler(Events.ADMIN_PERMISSIONS, root, function(permissions)
    if permissions and permissions.viewStats then
        buildStatsTabIfPermitted()
    end
end)

local function formatDuration(totalSeconds)
    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)

    local parts = {}
    if days > 0 then
        parts[#parts + 1] = days .. "d"
    end
    if days > 0 or hours > 0 then
        parts[#parts + 1] = hours .. "h"
    end
    parts[#parts + 1] = minutes .. "m"

    return table.concat(parts, " ")
end

local function populateStatsGrid()
    guiGridListClear(gridStats)

    for _, entry in ipairs(statsList) do
        local row = guiGridListAddRow(gridStats)
        guiGridListSetItemText(gridStats, row, columnStatsLogin, entry.login, false, false)
        guiGridListSetItemText(gridStats, row, columnStatsRole, ROLE_LABEL[entry.role] or tostring(entry.role), false, false)
        guiGridListSetItemText(gridStats, row, columnStatsDuty, formatDuration(entry.totalDutySeconds), false, false)
        guiGridListSetItemText(gridStats, row, columnStatsSessions, tostring(entry.sessionCount), false, false)
        guiGridListSetItemText(gridStats, row, columnStatsPenalties, tostring(entry.penaltiesIssued), false, false)
        guiGridListSetItemText(gridStats, row, columnStatsReports, tostring(entry.reportsResolved), false, false)
    end
end

function RequestStats()
    if not statsTabBuilt then
        return
    end
    triggerServerEvent(Events.ADMIN_REQUEST_STATS, resourceRoot)
end

addEvent(Events.ADMIN_STATS, true)
addEventHandler(Events.ADMIN_STATS, root, function(entries)
    if not statsTabBuilt then
        return
    end
    statsList = entries or {}
    populateStatsGrid()
end)

AdminGuiWindow_onPanelOpen(RequestStats)
