-- Never pass secrets, tokens, or full request payloads into `context` -
-- log identifiers and outcomes, not sensitive values.

Logger = Logger or {}

local LEVELS = {
    DEBUG = "DEBUG",
    INFO = "INFO",
    WARN = "WARN",
    ERROR = "ERROR",
    SECURITY = "SECURITY",
}

local function formatContext(context)
    if type(context) ~= "table" or not next(context) then
        return ""
    end

    local parts = {}
    for key, value in pairs(context) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end

    return " (" .. table.concat(parts, ", ") .. ")"
end

local function write(level, scope, message, context)
    local line = string.format("[%s] [%s] %s%s", level, tostring(scope), tostring(message), formatContext(context))
    outputServerLog(line)
end

--- @param scope string module name
-- @param message string
-- @param context table|nil extra structured context (no secrets)
Logger.debug = function(scope, message, context)
    write(LEVELS.DEBUG, scope, message, context)
end

Logger.info = function(scope, message, context)
    write(LEVELS.INFO, scope, message, context)
end

Logger.warn = function(scope, message, context)
    write(LEVELS.WARN, scope, message, context)
end

Logger.error = function(scope, message, context)
    write(LEVELS.ERROR, scope, message, context)
end

--- Dedicated channel for suspicious/abusive client behavior, distinct from
--- ordinary errors so it can later be routed to a security/anti-cheat sink.
Logger.security = function(scope, message, context)
    write(LEVELS.SECURITY, scope, message, context)
end

-- Flat exported wrappers so core_ui (and any other resource) can log
-- through the same structured Logger - see core_shared's Registry.lua
-- module comment for why these exist alongside the table methods (MTA
-- exports can't address Logger.info directly, only flat function names).
function loggerDebug(scope, message, context) Logger.debug(scope, message, context) end
function loggerInfo(scope, message, context) Logger.info(scope, message, context) end
function loggerWarn(scope, message, context) Logger.warn(scope, message, context) end
function loggerError(scope, message, context) Logger.error(scope, message, context) end
function loggerSecurity(scope, message, context) Logger.security(scope, message, context) end
