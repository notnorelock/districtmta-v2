--- @param raw string|nil
-- @return boolean ok, number|nil durationSecondsOrNilForPermanent, string|nil errorMessage
local function parseDuration(raw)
    if raw == nil or raw == "" or raw:lower() == "perm" or raw:lower() == "permanent" then
        return true, nil, nil
    end

    local amount, unit = raw:match("^(%d+)([mhd])$")
    if not amount then
        return false, nil, "Nieprawidłowy czas trwania '" .. raw .. "' - użyj np. 30m, 2h, 7d, lub 'perm'"
    end

    local seconds = tonumber(amount)
    if unit == "m" then
        seconds = seconds * 60
    elseif unit == "h" then
        seconds = seconds * 3600
    elseif unit == "d" then
        seconds = seconds * 86400
    end

    return true, seconds, nil
end

--- @param player element|nil issuer
-- @return number|nil issuedByAccountId
local function issuerAccountId(player)
    if CommandRegistry.isConsole(player) then
        return nil
    end
    return PlayerService.getAccountId(player)
end

CommandRegistry.register("ban", Permissions.Bit.BAN, function(player, targetLogin, durationRaw, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Użycie: /ban <login|id|nick> [czas|perm] [powód]", Enums.NotificationType.WARNING)
        return
    end

    local durationOk, durationSeconds, durationError = parseDuration(durationRaw)
    if not durationOk then
        CommandRegistry.reply(player, durationError, Enums.NotificationType.ERROR)
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        reason = nil
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.ban(account.id, {
            durationSeconds = durationSeconds,
            reason = reason,
            issuedByAccountId = issuerAccountId(player),
        }, function(ok, penaltyOrError)
            if not ok then
                CommandRegistry.reply(player, "Nie udało się zbanować: " .. tostring(penaltyOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AccountPenaltyCommands", "Ban issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                durationSeconds = durationSeconds,
                reason = reason,
            })
            CommandRegistry.reply(player, "Zbanowano '" .. account.login .. "'" .. (durationSeconds and (" na " .. durationRaw) or " na stałe"), Enums.NotificationType.SUCCESS)

            -- Ban only blocks future logins; also kick if connected now.
            for _, candidate in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(candidate) == account.id then
                    kickPlayer(candidate, "Zbanowano" .. (reason and (": " .. reason) or ""))
                    break
                end
            end
        end)
    end)
end)

CommandRegistry.register("unban", Permissions.Bit.REVOKE_PENALTY, function(player, targetLogin)
    if not targetLogin then
        CommandRegistry.reply(player, "Użycie: /unban <login|id|nick>", Enums.NotificationType.WARNING)
        return
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.isBanned(account.id, function(isBanned, activeBan)
            if not isBanned then
                CommandRegistry.reply(player, "'" .. account.login .. "' nie jest obecnie zbanowany", Enums.NotificationType.WARNING)
                return
            end

            AccountPenaltyService.revoke(activeBan.id, function(ok, affectedOrError)
                if not ok then
                    CommandRegistry.reply(player, "Nie udało się odbanować: " .. tostring(affectedOrError), Enums.NotificationType.ERROR)
                    return
                end

                Logger.security("AccountPenaltyCommands", "Ban revoked", {
                    targetAccountId = account.id,
                    targetLogin = account.login,
                    issuedBy = CommandRegistry.issuerLabel(player),
                })
                CommandRegistry.reply(player, "Odbanowano '" .. account.login .. "'", Enums.NotificationType.SUCCESS)
            end)
        end, function(message)
            CommandRegistry.reply(player, "Sprawdzenie bana nie powiodło się: " .. message, Enums.NotificationType.ERROR)
        end)
    end)
end)

CommandRegistry.register("mute", Permissions.Bit.MUTE, function(player, targetLogin, durationRaw, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Użycie: /mute <login|id|nick> [czas|perm] [powód]", Enums.NotificationType.WARNING)
        return
    end

    local durationOk, durationSeconds, durationError = parseDuration(durationRaw)
    if not durationOk then
        CommandRegistry.reply(player, durationError, Enums.NotificationType.ERROR)
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        reason = nil
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.mute(account.id, {
            durationSeconds = durationSeconds,
            reason = reason,
            issuedByAccountId = issuerAccountId(player),
        }, function(ok, penaltyOrError)
            if not ok then
                CommandRegistry.reply(player, "Nie udało się wyciszyć: " .. tostring(penaltyOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AccountPenaltyCommands", "Mute issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                durationSeconds = durationSeconds,
                reason = reason,
            })
            CommandRegistry.reply(player, "Wyciszono '" .. account.login .. "'" .. (durationSeconds and (" na " .. durationRaw) or " na stałe"), Enums.NotificationType.SUCCESS)
        end)
    end)
end)

CommandRegistry.register("warn", Permissions.Bit.WARN, function(player, targetLogin, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Użycie: /warn <login|id|nick> [powód]", Enums.NotificationType.WARNING)
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        reason = nil
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.warn(account.id, {
            reason = reason,
            issuedByAccountId = issuerAccountId(player),
        }, function(ok, penaltyOrError)
            if not ok then
                CommandRegistry.reply(player, "Nie udało się ostrzec: " .. tostring(penaltyOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AccountPenaltyCommands", "Warn issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                reason = reason,
            })
            CommandRegistry.reply(player, "Ostrzeżono '" .. account.login .. "'", Enums.NotificationType.SUCCESS)
        end)
    end)
end)

CommandRegistry.register("kick", Permissions.Bit.KICK, function(player, targetLogin, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Użycie: /kick <login|id|nick> [powód]", Enums.NotificationType.WARNING)
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        reason = nil
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.kick(account.id, {
            reason = reason,
            issuedByAccountId = issuerAccountId(player),
        }, function(ok, penaltyOrError)
            if not ok then
                CommandRegistry.reply(player, "Nie udało się zapisać wyrzucenia: " .. tostring(penaltyOrError), Enums.NotificationType.ERROR)
                return
            end

            Logger.security("AccountPenaltyCommands", "Kick issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                reason = reason,
            })
            CommandRegistry.reply(player, "Wyrzucono '" .. account.login .. "'", Enums.NotificationType.SUCCESS)

            for _, candidate in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(candidate) == account.id then
                    kickPlayer(candidate, "Wyrzucono" .. (reason and (": " .. reason) or ""))
                    break
                end
            end
        end)
    end)
end)
