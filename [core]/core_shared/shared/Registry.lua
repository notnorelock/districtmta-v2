-- core_shared exports one getter function per constant table (Events,
-- ErrorCodes, ValidationRules, Enums) since globals don't cross resource
-- boundaries. See docs/Architecture.md's GlobalResources.lua section.
-- Loaded as type="shared", so these getters exist independently in both
-- the server-side and client-side Lua states.

function getEvents()
    return Events
end

function getErrorCodes()
    return ErrorCodes
end

-- Returns ONLY the constant fields, not the predicate functions - MTA's
-- exports mechanism strips function values from returned tables. The
-- predicates are reached through their own flat functions below instead.
function getValidationRules()
    return {
        LOGIN_MIN_LENGTH = ValidationRules.LOGIN_MIN_LENGTH,
        LOGIN_MAX_LENGTH = ValidationRules.LOGIN_MAX_LENGTH,
        LOGIN_PATTERN = ValidationRules.LOGIN_PATTERN,
        EMAIL_MAX_LENGTH = ValidationRules.EMAIL_MAX_LENGTH,
        EMAIL_PATTERN = ValidationRules.EMAIL_PATTERN,
        PASSWORD_MIN_LENGTH = ValidationRules.PASSWORD_MIN_LENGTH,
        PASSWORD_MAX_LENGTH = ValidationRules.PASSWORD_MAX_LENGTH,
        MAX_ENDPOINT_LENGTH = ValidationRules.MAX_ENDPOINT_LENGTH,
        MAX_ARGUMENT_COUNT = ValidationRules.MAX_ARGUMENT_COUNT,
        MAX_STRING_ARGUMENT_LENGTH = ValidationRules.MAX_STRING_ARGUMENT_LENGTH,
    }
end

function getEnums()
    return Enums
end

-- Returns only the constant key tables, not accountField - MTA's exports
-- mechanism strips function fields from returned tables. accountField is
-- reached through its own flat function below instead.
function getElementData()
    return {
        Player = ElementData.Player,
        Account = ElementData.Account,
    }
end

function elementDataAccountField(field)
    return ElementData.accountField(field)
end

-- Flat exported wrappers for ValidationRules' predicate/normalizer functions.
function validationRulesIsValidLogin(login)
    return ValidationRules.isValidLogin(login)
end

function validationRulesIsValidEmail(email)
    return ValidationRules.isValidEmail(email)
end

function validationRulesNormalizeLogin(login)
    return ValidationRules.normalizeLogin(login)
end

function validationRulesNormalizeEmail(email)
    return ValidationRules.normalizeEmail(email)
end

function validationRulesIsValidPassword(password)
    return ValidationRules.isValidPassword(password)
end

-- Builds a FetchBridge response envelope - shared so every
-- endpoint-owning resource returns the same shape.
-- @param data any plain data to attach as the success payload
function successResponse(data)
    return { success = true, data = data }
end

--- @param code string|nil one of ErrorCodes' values - defaults to INTERNAL_ERROR
-- @param message string|nil optional safe/localizable detail, never a raw Lua error
function errorResponse(code, message)
    return { success = false, error = { code = code or ErrorCodes.INTERNAL_ERROR, message = message } }
end
