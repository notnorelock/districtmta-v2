-- Thin facade over the Report Active Record model - ReportService calls
-- this, never Report/Model/QueryBuilder directly.
ReportRepository = ReportRepository or {}

--- @param data table { reporterAccountId, reportedAccountId, reason }
-- @param callback function(ok: boolean, reportOrError: table|string)
ReportRepository.create = function(data, callback)
    Report:create({
        reporter_account_id = data.reporterAccountId,
        reported_account_id = data.reportedAccountId,
        reason = data.reason,
    }, callback)
end

--- @param id number
-- @param callback function(ok: boolean, reportOrError: table|nil|string)
ReportRepository.findById = function(id, callback)
    Report:find(id, callback)
end

--- Every open report, oldest first - so admins naturally work through
--- the queue in the order reports came in, same as any support queue.
-- @param callback function(ok: boolean, reportsOrError: table|string)
ReportRepository.findOpen = function(callback)
    Report:where("status", Enums.ReportStatus.OPEN):orderBy("created_at", "ASC"):get(callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, reportsOrError: table|string)
ReportRepository.findByReportedAccountId = function(accountId, callback)
    Report:where("reported_account_id", accountId):orderBy("created_at", "DESC"):get(callback)
end

--- @param resolvedByAccountId number
-- @param callback function(ok: boolean, countOrError: number|string)
ReportRepository.countResolvedByAccountId = function(resolvedByAccountId, callback)
    Report:where("resolved_by_account_id", resolvedByAccountId):count(callback)
end

--- @param id number
-- @param resolvedByAccountId number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
ReportRepository.resolve = function(id, resolvedByAccountId, callback)
    Report:query():where("id", id):update({
        status = Enums.ReportStatus.RESOLVED,
        resolved_by_account_id = resolvedByAccountId,
        resolved_at = os.date("!%Y-%m-%d %H:%M:%S"),
    }, callback)
end
