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

--- @param player element|nil issuer (nil/false = server console -> outputServerLog)
-- @param message string
CommandRegistry.reply = function(player, message)
    if CommandRegistry.isConsole(player) then
        outputServerLog(message)
    else
        outputChatBox(message, player, 200, 200, 200)
    end
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
        CommandRegistry.reply(player, "Znaleziono więcej niż jednego gracza - podaj więcej liter nicku lub użyj numeru gracza.")
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
            CommandRegistry.reply(player, "Lookup failed: " .. tostring(account))
            return
        end
        if not account then
            CommandRegistry.reply(player, "No account found matching '" .. tostring(target) .. "'")
            return
        end
        onFound(account)
    end)
end
