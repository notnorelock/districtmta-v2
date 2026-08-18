-- Canonical element data key registry - every setElementData/
-- getElementData/removeElementData key used across resources should be
-- read from here instead of typed as a raw string literal at the call
-- site, same reasoning as Events.lua's event name registry.

ElementData = {
    Player = {
        LOGGED = "player:logged",
        SPAWNED = "player:spawned",
        ADMIN = "player:admin",
        ID = "player:id",
        SKIN = "player:skin",
        SESSION_KEY = "player:sessionKey",
    },
    Account = {
        PREMIUM = "account:premium",
        MUTE = "account:mute",
    },
}

-- AuthUiController.lua mirrors most of an account row's own columns onto
-- "account:<field>" element data dynamically (id, role, created_at, ...)
-- rather than one constant per column - this builds that key consistently
-- instead of every call site formatting the string by hand.
-- @param field string account column name, e.g. "id" or "role"
-- @return string
ElementData.accountField = function(field)
    return "account:" .. field
end
