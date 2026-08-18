-- /duty, /report, /apanel, /reports - see docs/Architecture.md's
-- "Admin duty, panel, and reports" section.
CommandRegistry.register("duty", Permissions.Bit.TOGGLE_DUTY, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/duty can only be used in-game")
        return
    end

    local nowOnDuty = not PlayerService.isOnDuty(player)
    PlayerService.setDuty(player, nowOnDuty)

    local accountId = PlayerService.getAccountId(player)
    if nowOnDuty then
        AdminDutyStatsService.startSession(accountId)
    else
        AdminDutyStatsService.finishSession(accountId)
    end

    Logger.security("AdminCommands", "Duty toggled", {
        player = getPlayerName(player),
        accountId = accountId,
        onDuty = nowOnDuty,
    })
    CommandRegistry.reply(player, nowOnDuty and "Jesteś teraz na służbie." or "Zszedłeś ze służby.")

    -- core_admin's KeyBinds.lua binds/unbinds F6/F7 off this - see
    -- Events.ADMIN_DUTY_CHANGED's own comment.
    triggerClientEvent(player, Events.ADMIN_DUTY_CHANGED, player, nowOnDuty)
end)

CommandRegistry.register("report", nil, function(player, target, ...)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/report can only be used in-game")
        return
    end

    local reporterAccountId = PlayerService.getAccountId(player)
    if not reporterAccountId then
        CommandRegistry.reply(player, "Musisz być zalogowany, aby zgłosić gracza.")
        return
    end

    if not target then
        CommandRegistry.reply(player, "Usage: /report <login|id|nick> <powód>")
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        CommandRegistry.reply(player, "Usage: /report <login|id|nick> <powód>")
        return
    end

    CommandRegistry.resolveTargetAccount(player, target, function(reportedAccount)
        ReportService.create(reporterAccountId, reportedAccount.id, reason, function(report)
            CommandRegistry.reply(player, "Zgłoszenie na '" .. reportedAccount.login .. "' zostało wysłane.")
        end, function(code, message)
            CommandRegistry.reply(player, "Nie udało się wysłać zgłoszenia: " .. tostring(message or code))
        end)
    end)
end)

CommandRegistry.register("reports", Permissions.Bit.VIEW_REPORTS, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/reports can only be used in-game")
        return
    end

    triggerClientEvent(player, Events.REPORTS_OVERLAY_TOGGLE, player)
end)

CommandRegistry.register("apanel", Permissions.Bit.ADMIN_PANEL, function(player)
    if CommandRegistry.isConsole(player) then
        CommandRegistry.reply(player, "/apanel can only be used in-game")
        return
    end

    triggerClientEvent(player, Events.ADMIN_PANEL_TOGGLE, player)
end)
