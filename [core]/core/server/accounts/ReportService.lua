-- Business logic for the player report domain - see docs/Architecture.md's
-- "Reports" section for the report/resolve lifecycle.
ReportService = ReportService or {}

addEvent(Events.REPORT_CREATED, true)

local REASON_MAX_LENGTH = 255

--- Files a new report against an account.
-- @param reporterAccountId number
-- @param reportedAccountId number
-- @param reason string
-- @param onSuccess function(report: table)
-- @param onError function(code: string, message: string|nil)
ReportService.create = function(reporterAccountId, reportedAccountId, reason, onSuccess, onError)
    if type(reason) ~= "string" or #reason == 0 then
        onError(ErrorCodes.INVALID_ARGUMENTS, "Reason is required")
        return
    end
    if #reason > REASON_MAX_LENGTH then
        onError(ErrorCodes.INVALID_ARGUMENTS, "Reason must be at most " .. REASON_MAX_LENGTH .. " characters")
        return
    end
    if reporterAccountId == reportedAccountId then
        onError(ErrorCodes.INVALID_ARGUMENTS, "Cannot report your own account")
        return
    end

    ReportRepository.create({
        reporterAccountId = reporterAccountId,
        reportedAccountId = reportedAccountId,
        reason = reason,
    }, function(ok, reportOrError)
        if not ok then
            Logger.error("ReportService", "ReportRepository.create failed", { error = tostring(reportOrError) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end

        Logger.info("ReportService", "Report filed", {
            reportId = reportOrError.id,
            reporterAccountId = reporterAccountId,
            reportedAccountId = reportedAccountId,
        })

        triggerEvent(Events.REPORT_CREATED, resourceRoot, reportOrError)
        onSuccess(reportOrError)
    end)
end

--- @param callback function(ok: boolean, reportsOrError: table|string)
ReportService.listOpen = function(callback)
    ReportRepository.findOpen(callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, reportsOrError: table|string)
ReportService.listForAccount = function(accountId, callback)
    ReportRepository.findByReportedAccountId(accountId, callback)
end

--- Marks a report resolved.
-- @param reportId number
-- @param resolvedByAccountId number
-- @param onSuccess function()
-- @param onError function(code: string, message: string|nil)
ReportService.resolve = function(reportId, resolvedByAccountId, onSuccess, onError)
    ReportRepository.findById(reportId, function(ok, report)
        if not ok then
            Logger.error("ReportService", "ReportRepository.findById failed", { error = tostring(report) })
            onError(ErrorCodes.INTERNAL_ERROR)
            return
        end
        if not report then
            onError(ErrorCodes.REPORT_NOT_FOUND)
            return
        end
        if report.status == Enums.ReportStatus.RESOLVED then
            onError(ErrorCodes.INVALID_ARGUMENTS, "Report is already resolved")
            return
        end

        ReportRepository.resolve(reportId, resolvedByAccountId, function(resolveOk, affectedOrError)
            if not resolveOk then
                Logger.error("ReportService", "ReportRepository.resolve failed", { error = tostring(affectedOrError) })
                onError(ErrorCodes.INTERNAL_ERROR)
                return
            end

            Logger.info("ReportService", "Report resolved", {
                reportId = reportId,
                resolvedByAccountId = resolvedByAccountId,
            })
            onSuccess()
        end)
    end)
end
