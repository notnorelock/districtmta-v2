-- Maps each Enums.AccountRole to a permission bitmask - see
-- docs/Architecture.md's "Account roles and permissions" section.
Permissions = Permissions or {}

Permissions.Bit = {
    WARN = 1,
    MUTE = 2,
    KICK = 4,
    BAN = 8,
    VIEW_PENALTY_HISTORY = 16,
    REVOKE_PENALTY = 32,
    SET_ROLE = 64,
    ADMIN_PANEL = 128,
    TOGGLE_DUTY = 256,
    VIEW_REPORTS = 512,
    RESOLVE_REPORTS = 1024,
    VIEW_STATS = 2048,
    TELEPORT = 4096,
    HEAL = 8192,
    JETPACK = 16384,
}

local function bitOr(...)
    local result = 0
    for _, value in ipairs({ ... }) do
        result = result + value
    end
    return result
end

-- Built additively - each role includes everything the role below it has.
local WARN_MUTE_KICK = bitOr(Permissions.Bit.WARN, Permissions.Bit.MUTE, Permissions.Bit.KICK)
local MODERATOR_PERMISSIONS = bitOr(
    WARN_MUTE_KICK,
    Permissions.Bit.VIEW_PENALTY_HISTORY,
    Permissions.Bit.ADMIN_PANEL,
    Permissions.Bit.TOGGLE_DUTY,
    Permissions.Bit.VIEW_REPORTS,
    Permissions.Bit.RESOLVE_REPORTS,
    Permissions.Bit.TELEPORT,
    Permissions.Bit.HEAL,
    Permissions.Bit.JETPACK
)
local ADMINISTRATOR_PERMISSIONS = bitOr(MODERATOR_PERMISSIONS, Permissions.Bit.BAN, Permissions.Bit.REVOKE_PENALTY)
-- VIEW_STATS is RCON+/BOARD-only, deliberately not in ADMINISTRATOR_PERMISSIONS.
local RCON_PERMISSIONS = bitOr(ADMINISTRATOR_PERMISSIONS, Permissions.Bit.SET_ROLE, Permissions.Bit.VIEW_STATS)

local ROLE_PERMISSIONS = {
    [Enums.AccountRole.PLAYER] = 0,
    [Enums.AccountRole.VETERAN] = 0,
    [Enums.AccountRole.SUPPORTER] = MODERATOR_PERMISSIONS,
    [Enums.AccountRole.MODERATOR] = MODERATOR_PERMISSIONS,
    [Enums.AccountRole.ADMINISTRATOR] = ADMINISTRATOR_PERMISSIONS,
    [Enums.AccountRole.RCON] = RCON_PERMISSIONS,
    [Enums.AccountRole.BOARD] = RCON_PERMISSIONS,
}

--- @param role number one of Enums.AccountRole's values
-- @return number bitmask
Permissions.maskForRole = function(role)
    return ROLE_PERMISSIONS[role] or 0
end

--- @param account table internal account record (snake_case DB columns) - or a bare role number
-- @param bit number one of Permissions.Bit's values
-- @return boolean
Permissions.has = function(accountOrRole, bit)
    local role = type(accountOrRole) == "table" and accountOrRole.role or accountOrRole
    local mask = Permissions.maskForRole(role or Enums.AccountRole.PLAYER)
    return math.floor(mask / bit) % 2 == 1
end

-- Chat/nickname display color per role - "#RRGGBB". PLAYER/VETERAN/
-- SUPPORTER have no entry (nil): they show premium gold or default white.
local ROLE_COLORS = {
    [Enums.AccountRole.SUPPORTER] = "#144B97",
    [Enums.AccountRole.MODERATOR] = "#4CAF50",
    [Enums.AccountRole.ADMINISTRATOR] = "#E53935",
    [Enums.AccountRole.RCON] = "#9C27B0",
    [Enums.AccountRole.BOARD] = "#FF6F00",
}

--- @param role number|nil one of Enums.AccountRole's values
-- @return string|nil "#RRGGBB", or nil if `role` has no fixed color (see ROLE_COLORS)
Permissions.colorForRole = function(role)
    return ROLE_COLORS[role]
end

function permissionsColorForRole(role) return Permissions.colorForRole(role) end
function permissionsHasRole(role, bit) return Permissions.has(role, bit) end

function getPermissionsBit()
    return Permissions.Bit
end
