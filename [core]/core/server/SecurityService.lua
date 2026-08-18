SecurityService = SecurityService or {}

local SECURITY_REPORT_EVENT = "core:security.report"
addEvent(SECURITY_REPORT_EVENT, true)

-- Codes that always end the offending player's session immediately - a
-- legitimate client (unmodified UI) can never trigger these, since the
-- corresponding buttons/commands are hidden/disabled client-side for a
-- player lacking the permission. Reaching the server-side handler anyway
-- means the client was modified to bypass that UI gating.
local KICK_ON_SIGHT_CODES = {
    UNAUTHORIZED_ADMIN_ACTION = true,
}

--- Reports a suspicious/abusive client action. Codes listed in
--- KICK_ON_SIGHT_CODES end the player's session immediately (zero
--- tolerance - see the table comment above for why that's safe here).
-- @param player element the offending player
-- @param code string short machine-readable reason, e.g. "UNKNOWN_ENDPOINT"
-- @param metadata table|nil additional non-sensitive context
SecurityService.report = function(player, code, metadata)
    Logger.security("SecurityService", code, {
        player = isElement(player) and getPlayerName(player) or "unknown",
        code = code,
    })

    triggerEvent(SECURITY_REPORT_EVENT, resourceRoot, player, code, metadata or {})

    if KICK_ON_SIGHT_CODES[code] and isElement(player) then
        kickPlayer(player, "Wykryto nieautoryzowaną modyfikację klienta")
    end
end

-- Flat exported wrapper - see core_shared's Registry.lua module comment
-- for why this exists alongside the table method.
function securityServiceReport(player, code, metadata) SecurityService.report(player, code, metadata) end
