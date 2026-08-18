SecurityService = SecurityService or {}

local SECURITY_REPORT_EVENT = "core:security.report"
addEvent(SECURITY_REPORT_EVENT, true)

--- Reports a suspicious/abusive client action.
-- @param player element the offending player
-- @param code string short machine-readable reason, e.g. "UNKNOWN_ENDPOINT"
-- @param metadata table|nil additional non-sensitive context
SecurityService.report = function(player, code, metadata)
    Logger.security("SecurityService", code, {
        player = isElement(player) and getPlayerName(player) or "unknown",
        code = code,
    })

    triggerEvent(SECURITY_REPORT_EVENT, resourceRoot, player, code, metadata or {})
end

-- Flat exported wrapper - see core_shared's Registry.lua module comment
-- for why this exists alongside the table method.
function securityServiceReport(player, code, metadata) SecurityService.report(player, code, metadata) end
