--- @param raw string|nil
-- @return boolean ok, number|nil durationSecondsOrNilForPermanent, string|nil errorMessage
local function parseDuration(raw)
    if raw == nil or raw == "" or raw:lower() == "perm" or raw:lower() == "permanent" then
        return true, nil, nil
    end

    local amount, unit = raw:match("^(%d+)([mhd])$")
    if not amount then
        return false, nil, "Invalid duration '" .. raw .. "' - use e.g. 30m, 2h, 7d, or 'perm'"
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
        CommandRegistry.reply(player, "Usage: /ban <login|id|nick> [duration|perm] [reason]")
        return
    end

    local durationOk, durationSeconds, durationError = parseDuration(durationRaw)
    if not durationOk then
        CommandRegistry.reply(player, durationError)
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
                CommandRegistry.reply(player, "Ban failed: " .. tostring(penaltyOrError))
                return
            end

            Logger.security("AccountPenaltyCommands", "Ban issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                durationSeconds = durationSeconds,
                reason = reason,
            })
            CommandRegistry.reply(player, "Banned '" .. account.login .. "'" .. (durationSeconds and (" for " .. durationRaw) or " permanently"))

            -- Ban only blocks future logins; also kick if connected now.
            for _, candidate in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(candidate) == account.id then
                    kickPlayer(candidate, "Banned" .. (reason and (": " .. reason) or ""))
                    break
                end
            end
        end)
    end)
end)

CommandRegistry.register("unban", Permissions.Bit.REVOKE_PENALTY, function(player, targetLogin)
    if not targetLogin then
        CommandRegistry.reply(player, "Usage: /unban <login|id|nick>")
        return
    end

    CommandRegistry.resolveTargetAccount(player, targetLogin, function(account)
        AccountPenaltyService.isBanned(account.id, function(isBanned, activeBan)
            if not isBanned then
                CommandRegistry.reply(player, "'" .. account.login .. "' is not currently banned")
                return
            end

            AccountPenaltyService.revoke(activeBan.id, function(ok, affectedOrError)
                if not ok then
                    CommandRegistry.reply(player, "Unban failed: " .. tostring(affectedOrError))
                    return
                end

                Logger.security("AccountPenaltyCommands", "Ban revoked", {
                    targetAccountId = account.id,
                    targetLogin = account.login,
                    issuedBy = CommandRegistry.issuerLabel(player),
                })
                CommandRegistry.reply(player, "Unbanned '" .. account.login .. "'")
            end)
        end, function(message)
            CommandRegistry.reply(player, "isBanned check failed: " .. message)
        end)
    end)
end)

CommandRegistry.register("mute", Permissions.Bit.MUTE, function(player, targetLogin, durationRaw, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Usage: /mute <login|id|nick> [duration|perm] [reason]")
        return
    end

    local durationOk, durationSeconds, durationError = parseDuration(durationRaw)
    if not durationOk then
        CommandRegistry.reply(player, durationError)
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
                CommandRegistry.reply(player, "Mute failed: " .. tostring(penaltyOrError))
                return
            end

            Logger.security("AccountPenaltyCommands", "Mute issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                durationSeconds = durationSeconds,
                reason = reason,
            })
            CommandRegistry.reply(player, "Muted '" .. account.login .. "'" .. (durationSeconds and (" for " .. durationRaw) or " permanently"))
        end)
    end)
end)

CommandRegistry.register("warn", Permissions.Bit.WARN, function(player, targetLogin, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Usage: /warn <login|id|nick> [reason]")
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
                CommandRegistry.reply(player, "Warn failed: " .. tostring(penaltyOrError))
                return
            end

            Logger.security("AccountPenaltyCommands", "Warn issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                reason = reason,
            })
            CommandRegistry.reply(player, "Warned '" .. account.login .. "'")
        end)
    end)
end)

CommandRegistry.register("kick", Permissions.Bit.KICK, function(player, targetLogin, ...)
    if not targetLogin then
        CommandRegistry.reply(player, "Usage: /kick <login|id|nick> [reason]")
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
                CommandRegistry.reply(player, "Kick log failed: " .. tostring(penaltyOrError))
                return
            end

            Logger.security("AccountPenaltyCommands", "Kick issued", {
                targetAccountId = account.id,
                targetLogin = account.login,
                issuedBy = CommandRegistry.issuerLabel(player),
                reason = reason,
            })
            CommandRegistry.reply(player, "Kicked '" .. account.login .. "'")

            for _, candidate in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(candidate) == account.id then
                    kickPlayer(candidate, "Kicked" .. (reason and (": " .. reason) or ""))
                    break
                end
            end
        end)
    end)
end)
