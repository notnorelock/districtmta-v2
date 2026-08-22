-- Thin wrapper over addCommandHandler for admin commands - permission
-- check, issuer-aware reply, target resolution. See docs/Architecture.md's
-- "Account roles and permissions" section for why this uses
-- Permissions.has rather than MTA's ACL.
CommandRegistry = CommandRegistry or {}

--- @param player element|nil
-- @return boolean true if `player` is nil/false, MTA's convention for a
--         command issued from the server's own console/window rather
--         than an in-game player's F8 console
CommandRegistry.isConsole = function(player)
    return player == nil or player == false
end

-- title text NotificationsComponent.lua's own categories fall back to
-- when properties.title isn't given - mirrored here so a command reply's
-- toast heading reads the same as every other one in the project
-- ("Sukces"/"Błąd"/...) rather than a generic "Komenda" label.
local NOTIFICATION_TYPE_TITLE = {
    success = "Sukces",
    error = "Błąd",
    info = "Informacja",
    warning = "Ostrzeżenie",
}

--- @param player element|nil issuer (nil/false = server console -> outputServerLog)
-- @param message string
-- @param notificationType string|nil one of Enums.NotificationType
--        ("success"|"error"|"info"|"warning") - defaults to "info". Console
--        replies ignore this entirely (outputServerLog has no concept of
--        type/color); a real player gets it as a native ui_hud toast
--        instead of a plain chat line - message carries the actual reply
--        text, title is just the type's own generic label.
CommandRegistry.reply = function(player, message, notificationType)
    if CommandRegistry.isConsole(player) then
        outputServerLog(message)
        return
    end

    local type_ = notificationType or Enums.NotificationType.INFO
    NotificationService.send(player, {
        type = type_,
        title = NOTIFICATION_TYPE_TITLE[type_] or NOTIFICATION_TYPE_TITLE[Enums.NotificationType.INFO],
        message = message,
    })
end

--- @param player element|nil issuer
-- @return string "console" or the player's name, for Logger.security context
CommandRegistry.issuerLabel = function(player)
    if CommandRegistry.isConsole(player) then
        return "console"
    end
    return getPlayerName(player)
end

--- @param player element|nil issuer (server console is always allowed)
-- @param permissionBit number|nil one of Permissions.Bit's values - nil
--        means "no permission required" (e.g. a command any logged-in
--        player, or even the console alone, should be able to run)
-- @return boolean allowed
local function hasRequiredPermission(player, permissionBit)
    if CommandRegistry.isConsole(player) then
        return true
    end
    if permissionBit == nil then
        return true
    end
    local account = PlayerService.getAccount(player)
    return account ~= nil and Permissions.has(account, permissionBit)
end

--- @param name string bare command name, e.g. "ban" (no leading "/")
-- @param permissionBit number|nil one of Permissions.Bit's values (nil = no permission required)
-- @param handler function(player: element|nil, ...: string)
CommandRegistry.register = function(name, permissionBit, handler)
    addCommandHandler(name, function(player, _, ...)
        if not hasRequiredPermission(player, permissionBit) then
            return
        end
        handler(player, ...)
    end)
end

--- Tries a runtime id/name-fragment match against connected players
--- first, falling back to a login lookup (also covers offline accounts).
-- @param player element|nil issuer, for the reply destination
-- @param target string login, runtime id, or name fragment
-- @param onFound function(account: table)
CommandRegistry.resolveTargetAccount = function(player, target, onFound)
    local onlineMatch, ambiguous = PlayerId.tryResolve(target)

    if ambiguous then
        CommandRegistry.reply(player, "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza.", Enums.NotificationType.ERROR)
        return
    end

    if onlineMatch then
        local account = PlayerService.getAccount(onlineMatch)
        if account then
            onFound(account)
            return
        end
        -- Matched a connected player, but they're not logged in (no
        -- account context yet) - fall through to the login lookup below,
        -- same as if PlayerId.tryResolve hadn't matched anyone at all.
    end

    AccountRepository.findByLogin(ValidationRules.normalizeLogin(tostring(target)), function(ok, account)
        if not ok then
            CommandRegistry.reply(player, "Wyszukiwanie nie powiodło się: " .. tostring(account), Enums.NotificationType.ERROR)
            return
        end
        if not account then
            CommandRegistry.reply(player, "Nie znaleziono konta pasującego do '" .. tostring(target) .. "'", Enums.NotificationType.ERROR)
            return
        end
        onFound(account)
    end)
end
