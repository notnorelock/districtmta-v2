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
        return nil, "Unknown role '" .. raw .. "' - valid roles: " .. table.concat(names, ", ")
    end
    return role, nil
end

CommandRegistry.register("setrole", Permissions.Bit.SET_ROLE, function(player, targetLogin, roleRaw)
    if not targetLogin or not roleRaw then
        CommandRegistry.reply(player, "Usage: /setrole <login|id|nick> <role>")
        return
    end

    local role, roleError = parseRole(roleRaw)
    if not role then
        CommandRegistry.reply(player, roleError)
        return
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountService.setRole(account.id, role, function(setOk, affectedOrError)
            if not setOk then
                CommandRegistry.reply(player, "Failed to set role: " .. tostring(affectedOrError))
                return
            end

            Logger.security("AccountRoleCommands", "Role changed", {
                targetAccountId = account.id,
                targetLogin = account.login,
                newRole = roleRaw:upper(),
                issuedBy = CommandRegistry.issuerLabel(player),
            })
            CommandRegistry.reply(player, "Set '" .. account.login .. "' role to " .. roleRaw:upper())
        end)
    end)
end)
