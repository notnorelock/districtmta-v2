-- Shared validation constants and predicate helpers. Mirrored (not
-- imported) on the frontend for UX only - the server is always the
-- authoritative validator.

ValidationRules = {
    LOGIN_MIN_LENGTH = 3,
    LOGIN_MAX_LENGTH = 24,
    LOGIN_PATTERN = "^[A-Za-z0-9_]+$",

    EMAIL_MAX_LENGTH = 254,
    EMAIL_PATTERN = "^[%w%.%+%-_]+@[%w%-_]+%.[%a][%a%.]*$",

    PASSWORD_MIN_LENGTH = 8,
    PASSWORD_MAX_LENGTH = 128,

    -- FetchBridge request envelope limits
    MAX_ENDPOINT_LENGTH = 64,
    MAX_ARGUMENT_COUNT = 16,
    MAX_STRING_ARGUMENT_LENGTH = 1024,
}

ValidationRules.isValidLogin = function(login)
    if type(login) ~= "string" then
        return false
    end

    local length = #login
    if length < ValidationRules.LOGIN_MIN_LENGTH or length > ValidationRules.LOGIN_MAX_LENGTH then
        return false
    end

    return string.match(login, ValidationRules.LOGIN_PATTERN) ~= nil
end

ValidationRules.isValidEmail = function(email)
    if type(email) ~= "string" then
        return false
    end

    local length = #email
    if length < 3 or length > ValidationRules.EMAIL_MAX_LENGTH then
        return false
    end

    return string.match(email, ValidationRules.EMAIL_PATTERN) ~= nil
end

ValidationRules.isValidPassword = function(password)
    if type(password) ~= "string" then
        return false
    end

    local length = #password
    return length >= ValidationRules.PASSWORD_MIN_LENGTH and length <= ValidationRules.PASSWORD_MAX_LENGTH
end

--- Normalizes a login for case-insensitive comparison/storage lookups.
ValidationRules.normalizeLogin = function(login)
    return string.lower(login)
end

--- Normalizes an email for comparison/storage lookups.
ValidationRules.normalizeEmail = function(email)
    return string.lower(email)
end
