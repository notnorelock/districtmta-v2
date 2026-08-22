-- /setrole - see docs/Architecture.md's "Account roles and permissions" section.

--- @param raw string
-- @return number|nil role, string|nil errorMessage
local function parseRole(raw)
    local roleName = raw:upper()
    local role = Enums.AccountRole[roleName]
    if role == nil then
        local names = {}
        for name in pairs(Enums.AccountRole) do
            names[#names + 1] = name
        end
        table.sort(names)
        return nil, "Nieznana ranga '" .. raw .. "' - dostępne rangi: " .. table.concat(names, ", ")
    end
    return role, nil
end

CommandRegistry.register("setrole", Permissions.Bit.SET_ROLE, function(player, targetLogin, roleRaw)
    if not targetLogin or not roleRaw then
        CommandRegistry.reply(player, "Użycie: /setrole <login|id|nick> <ranga>", Enums.NotificationType.WARNING)
        return
    end

    local role, roleError = parseRole(roleRaw)
    if not role then
        CommandRegistry.reply(player, roleError, Enums.NotificationType.ERROR)
        return
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountService.setRole(account.id, role, function(setOk, affectedOrError)
            if not setOk then
                CommandRegistry.reply(player, "Nie udało się ustawić rangi: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AccountRoleCommands", "Role changed", {
                targetAccountId = account.id,
                targetLogin = account.login,
                newRole = roleRaw:upper(),
                issuedBy = CommandRegistry.issuerLabel(player),
            })
            CommandRegistry.reply(player, "Ustawiono rangę '" .. account.login .. "' na " .. roleRaw:upper(), Enums.NotificationType.SUCCESS)
        end)
    end)
end)
