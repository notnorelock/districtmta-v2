-- Local copy of core's Logger, duplicated rather than proxied across the resource boundary.

Logger = Logger or {}

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

Logger.debug = function(scope, message, context)
    outputDebugString(string.format("[DEBUG] [%s] %s%s", tostring(scope), tostring(message), formatContext(context)))
end

Logger.warn = function(scope, message, context)
    outputDebugString(string.format("[WARN] [%s] %s%s", tostring(scope), tostring(message), formatContext(context)), 2)
end

Logger.error = function(scope, message, context)
    outputDebugString(string.format("[ERROR] [%s] %s%s", tostring(scope), tostring(message), formatContext(context)), 1)
end
