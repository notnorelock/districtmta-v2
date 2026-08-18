-- Server-side handlers backing core_admin's native dxGUI panel (plain
-- triggerServerEvent/triggerClientEvent, no FetchBridge/CEF involved).
-- Every handler does its own Permissions.has check and silently ignores
-- an unauthorized caller (no error surface to report to here).
--
-- IMPORTANT: handlers read `client`, never `source` - triggerServerEvent
-- from the dxGUI always targets resourceRoot, so `source` is the resource
-- element, not the calling player; `client` is the real caller.

addEvent(Events.ADMIN_REQUEST_PLAYER_LIST, true)
addEvent(Events.ADMIN_PLAYER_LIST, true)
addEvent(Events.ADMIN_REQUEST_REPORT_LIST, true)
addEvent(Events.ADMIN_REPORT_LIST, true)
addEvent(Events.ADMIN_RESOLVE_REPORT, true)
addEvent(Events.ADMIN_ISSUE_PENALTY, true)
addEvent(Events.ADMIN_REPORT_CREATED_NOTICE, true)
addEvent(Events.ADMIN_DUTY_CHANGED, true)
addEvent(Events.ADMIN_REQUEST_DUTY_STATUS, true)
addEvent(Events.ADMIN_REQUEST_STATS, true)
addEvent(Events.ADMIN_STATS, true)
addEvent(Events.ADMIN_PERMISSIONS, true)

--- @param player element
-- @param bit number one of Permissions.Bit's values
-- @return boolean
local function callerHasPermission(player, bit)
    local account = PlayerService.getAccount(player)
    return account ~= nil and Permissions.has(account, bit)
end

--- @param player element
-- @param account table internal account record
-- @return table { runtimeId, id, login, role, onDuty }
local function toPlayerListEntry(player, account)
    return {
        runtimeId = PlayerId.of(player),
        id = account.id,
        login = account.login,
        role = account.role,
        onDuty = PlayerService.isOnDuty(player),
    }
end

--- @param report table internal report record (snake_case DB columns)
-- @return table camelCase DTO (no login fields - see resolveReportLogins
--         below for the version the dxGUI panel/overlay actually renders)
local function toPublicReport(report)
    return {
        id = report.id,
        reporterAccountId = report.reporter_account_id,
        reportedAccountId = report.reported_account_id,
        reason = report.reason,
        status = report.status,
        createdAt = report.created_at,
        resolvedByAccountId = report.resolved_by_account_id,
    }
end

--- @param accountId number
-- @return string|nil account login if `accountId` belongs to a currently connected player
local function findOnlineAccountLogin(accountId)
    for _, candidate in ipairs(getElementsByType("player")) do
        local account = PlayerService.getAccount(candidate)
        if account and account.id == accountId then
            return account.login
        end
    end
    return nil
end

--- Resolves reporter/reported/resolver account ids into logins, mutating
--- each report DTO in place. Online accounts resolve via PlayerService;
--- offline ones are looked up once via AccountRepository.findById, deduped.
-- @param reports table array of toPublicReport(...) DTOs, mutated in place
-- @param onDone function() called once every DTO has its login fields set
local function resolveReportLogins(reports, onDone)
    local idsToLookUp = {}
    local idsPending = {}

    for _, report in ipairs(reports) do
        for _, field in ipairs({ "reporterAccountId", "reportedAccountId", "resolvedByAccountId" }) do
            local accountId = report[field]
            if accountId then
                local onlineLogin = findOnlineAccountLogin(accountId)
                if onlineLogin then
                    report[field:gsub("AccountId$", "Login")] = onlineLogin
                elseif not idsPending[accountId] then
                    idsPending[accountId] = true
                    idsToLookUp[#idsToLookUp + 1] = accountId
                end
            end
        end
    end

    if #idsToLookUp == 0 then
        onDone()
        return
    end

    local remaining = #idsToLookUp
    local loginById = {}

    local function finishIfDone()
        remaining = remaining - 1
        if remaining > 0 then
            return
        end

        for _, report in ipairs(reports) do
            for _, field in ipairs({ "reporterAccountId", "reportedAccountId", "resolvedByAccountId" }) do
                local accountId = report[field]
                local loginField = field:gsub("AccountId$", "Login")
                if accountId and not report[loginField] then
                    report[loginField] = loginById[accountId]
                end
            end
        end
        onDone()
    end

    for _, accountId in ipairs(idsToLookUp) do
        AccountRepository.findById(accountId, function(ok, accountOrError)
            if ok and accountOrError then
                loginById[accountId] = accountOrError.login
            else
                Logger.error("AdminGuiEndpoints", "AccountRepository.findById failed while resolving report login", {
                    accountId = accountId,
                    error = tostring(accountOrError),
                })
            end
            finishIfDone()
        end)
    end
end

-- Not gated behind callerHasPermission - only ever reflects the caller's
-- own duty status. Lets the client learn current duty state on its own start.
addEventHandler(Events.ADMIN_REQUEST_DUTY_STATUS, root, function()
    local player = client
    triggerClientEvent(player, Events.ADMIN_DUTY_CHANGED, player, PlayerService.isOnDuty(player))
end)

addEventHandler(Events.ADMIN_REQUEST_PLAYER_LIST, root, function()
    local player = client
    if not callerHasPermission(player, Permissions.Bit.ADMIN_PANEL) then
        return
    end

    local entries = {}
    for _, candidate in ipairs(getElementsByType("player")) do
        local candidateAccount = PlayerService.getAccount(candidate)
        if candidateAccount then
            entries[#entries + 1] = toPlayerListEntry(candidate, candidateAccount)
        end
    end

    triggerClientEvent(player, Events.ADMIN_PLAYER_LIST, player, entries)

    -- Piggybacks on the player-list request (fires once per panel open)
    -- rather than its own request/response pair.
    triggerClientEvent(player, Events.ADMIN_PERMISSIONS, player, {
        viewStats = callerHasPermission(player, Permissions.Bit.VIEW_STATS),
    })
end)

-- Gated behind VIEW_STATS specifically, not ADMIN_PANEL (stats tab is
-- RCON+/BOARD-only, unlike the rest of the panel).
addEventHandler(Events.ADMIN_REQUEST_STATS, root, function()
    local player = client
    if not callerHasPermission(player, Permissions.Bit.VIEW_STATS) then
        return
    end

    AdminDutyStatsService.statsForEveryAdmin(function(ok, entriesOrError)
        if not ok then
            Logger.error("AdminGuiEndpoints", "statsForEveryAdmin failed", { error = tostring(entriesOrError) })
            return
        end
        if isElement(player) then
            triggerClientEvent(player, Events.ADMIN_STATS, player, entriesOrError)
        end
    end)
end)

addEventHandler(Events.ADMIN_REQUEST_REPORT_LIST, root, function()
    local player = client
    if not callerHasPermission(player, Permissions.Bit.VIEW_REPORTS) then
        return
    end

    ReportService.listOpen(function(ok, reportsOrError)
        if not ok then
            Logger.error("AdminGuiEndpoints", "listOpen failed", { error = tostring(reportsOrError) })
            return
        end
        if not isElement(player) then
            return
        end

        local publicReports = {}
        for i, report in ipairs(reportsOrError) do
            publicReports[i] = toPublicReport(report)
        end

        resolveReportLogins(publicReports, function()
            if isElement(player) then
                triggerClientEvent(player, Events.ADMIN_REPORT_LIST, player, publicReports)
            end
        end)
    end)
end)

addEventHandler(Events.ADMIN_RESOLVE_REPORT, root, function(reportId)
    local player = client
    if not callerHasPermission(player, Permissions.Bit.RESOLVE_REPORTS) then
        return
    end
    if type(reportId) ~= "number" then
        return
    end

    local resolvedByAccountId = PlayerService.getAccountId(player)

    ReportService.resolve(reportId, resolvedByAccountId, function()
        if isElement(player) then
            triggerClientEvent(player, Events.ADMIN_REQUEST_REPORT_LIST, player)
        end
    end, function(code, message)
        Logger.error("AdminGuiEndpoints", "resolve failed", { code = code, message = message })
    end)
end)

local PENALTY_TYPE_PERMISSION = {
    [Enums.PenaltyType.WARN] = Permissions.Bit.WARN,
    [Enums.PenaltyType.MUTE] = Permissions.Bit.MUTE,
    [Enums.PenaltyType.KICK] = Permissions.Bit.KICK,
    [Enums.PenaltyType.BAN] = Permissions.Bit.BAN,
}

local PENALTY_ISSUER = {
    [Enums.PenaltyType.WARN] = function(...) return AccountPenaltyService.warn(...) end,
    [Enums.PenaltyType.MUTE] = function(...) return AccountPenaltyService.mute(...) end,
    [Enums.PenaltyType.KICK] = function(...) return AccountPenaltyService.kick(...) end,
    [Enums.PenaltyType.BAN] = function(...) return AccountPenaltyService.ban(...) end,
}

--- Single handler for every penalty type the dxGUI panel can issue.
-- @param data table { type, targetAccountId, reason?, durationSeconds? }
--        durationSeconds is optional (nil = permanent, BAN/MUTE only).
addEventHandler(Events.ADMIN_ISSUE_PENALTY, root, function(data)
    local player = client
    if type(data) ~= "table" or type(data.type) ~= "string" or type(data.targetAccountId) ~= "number" then
        return
    end

    local requiredBit = PENALTY_TYPE_PERMISSION[data.type]
    local issue = PENALTY_ISSUER[data.type]
    if not requiredBit or not issue then
        return
    end
    if not callerHasPermission(player, requiredBit) then
        return
    end

    local options = {
        reason = type(data.reason) == "string" and data.reason or nil,
        durationSeconds = type(data.durationSeconds) == "number" and data.durationSeconds or nil,
        issuedByAccountId = PlayerService.getAccountId(player),
    }

    issue(data.targetAccountId, options, function(ok, penaltyOrError)
        if not ok then
            Logger.error("AdminGuiEndpoints", "issuePenalty failed", { error = tostring(penaltyOrError) })
            return
        end

        Logger.security("AdminGuiEndpoints", "Penalty issued from admin panel", {
            type = data.type,
            targetAccountId = data.targetAccountId,
            issuedBy = getPlayerName(player),
        })

        -- BAN/KICK end the active session immediately, same as the F8 commands.
        if data.type == Enums.PenaltyType.BAN or data.type == Enums.PenaltyType.KICK then
            for _, candidate in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(candidate) == data.targetAccountId then
                    kickPlayer(candidate, data.type == Enums.PenaltyType.BAN and "Banned" or "Kicked")
                    break
                end
            end
        end
    end)
end)

-- Relays Events.REPORT_CREATED to every on-duty admin so the panel can
-- refresh immediately instead of on its next open/request.
addEventHandler(Events.REPORT_CREATED, root, function(report)
    local publicReport = toPublicReport(report)
    resolveReportLogins({ publicReport }, function()
        for _, player in ipairs(getElementsByType("player")) do
            if PlayerService.isOnDuty(player) then
                triggerClientEvent(player, Events.ADMIN_REPORT_CREATED_NOTICE, player, publicReport)
            end
        end
    end)
end)
