-- core_ui's own local copy, deliberately duplicated rather than proxied
-- to core - see docs/Architecture.md for the exports re-entrancy bug this avoids.
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

Logger.security = function(scope, message, context)
    write(LEVELS.SECURITY, scope, message, context)
end
