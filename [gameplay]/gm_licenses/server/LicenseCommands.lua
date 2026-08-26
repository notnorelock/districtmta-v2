-- Admin commands for the licenses system:
-- Starting an exam is no longer a command - walking into a category
-- marker opens a CEF dialog (LicenseExamService.lua's own
-- LICENSE_EXAM_DIALOG_OPEN/LICENSE_EXAM_DIALOG_START/LICENSE_QUIZ_ANSWER
-- handlers), see that file's own module comment.
-- /suspendlicense <player> <category> <hours|perm> [reason] - admin-only
--   (MANAGE_LICENSES), suspends a category for an ONLINE target (this
--   resource has no offline-account lookup, unlike core's own
--   CommandRegistry.resolveTargetAccount - see playerIdResolve's own
--   comment; the target must be connected right now).
-- /unsuspendlicense <player> <category> - admin-only, lifts an active suspension.

--- @param player element
-- @return boolean
local function isReady(player)
    return exports.core_shared:isPlayerReady(player)
end

--- @param player element
-- @return boolean
local function canManageLicenses(player)
    local role = PlayerService.getRole(player)
    if role == nil then
        return false
    end
    return Permissions.has(role, Permissions.Bit.MANAGE_LICENSES) == true
end

--- Same regex/unit shape as core/server/commands/AccountPenaltyCommands.lua's
-- own local parseDuration - duplicated here rather than shared cross-file
-- since it's a small local helper, not exported by core.
-- @param raw string|nil
-- @return boolean ok, string|nil expiresAtSql, string|nil errorMessage
local function parseDurationToExpiry(raw)
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

    return true, os.date("!%Y-%m-%d %H:%M:%S", os.time() + seconds), nil
end

addCommandHandler("suspendlicense", function(player, _, targetArg, categoryArg, durationRaw, ...)
    if not isElement(player) or not isReady(player) then
        return
    end
    if not canManageLicenses(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    if not targetArg or not categoryArg then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /suspendlicense <gracz> <A|B|C|D> [czas|perm] [powód]" })
        return
    end

    local category = tostring(categoryArg):upper()
    if not Enums.LicenseCategory[category] then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nieprawidłowa kategoria - dozwolone: A, B, C, D." })
        return
    end

    local durationOk, expiresAt, durationError = parseDurationToExpiry(durationRaw)
    if not durationOk then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = durationError })
        return
    end

    local reason = table.concat({ ... }, " ")
    if reason == "" then
        reason = nil
    end

    local target = playerIdResolve(player, targetArg)
    if not target then
        return
    end

    local targetAccountId = PlayerService.getAccountId(target)
    if not targetAccountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Gracz nie jest zalogowany na konto." })
        return
    end

    local issuerAccountId = PlayerService.getAccountId(player)

    LicenseBridge.call("createSuspension", {
        {
            accountId = targetAccountId,
            category = category,
            reason = reason,
            issuedByAccountId = issuerAccountId,
            expiresAt = expiresAt,
        },
    }, function(ok, suspensionOrError)
        if not ok then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zawiesić uprawnień: " .. tostring(suspensionOrError) })
            return
        end

        Logger.security("LicenseCommands", "License suspension issued", {
            targetAccountId = targetAccountId,
            targetPlayer = getPlayerName(target),
            category = category,
            issuedBy = getPlayerName(player),
            expiresAt = expiresAt,
            reason = reason,
        })

        if isElement(target) then
            LicenseExamService.resyncElementData(target)
        end

        NotificationService.send(player, {
            type = Enums.NotificationType.SUCCESS,
            message = "Zawieszono uprawnienia kat. " .. category .. " gracza '" .. getPlayerName(target) .. "'" .. (durationRaw and (" na " .. durationRaw) or " na stałe") .. ".",
        })
    end)
end)

addCommandHandler("unsuspendlicense", function(player, _, targetArg, categoryArg)
    if not isElement(player) or not isReady(player) then
        return
    end
    if not canManageLicenses(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    if not targetArg or not categoryArg then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /unsuspendlicense <gracz> <A|B|C|D>" })
        return
    end

    local category = tostring(categoryArg):upper()
    if not Enums.LicenseCategory[category] then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nieprawidłowa kategoria - dozwolone: A, B, C, D." })
        return
    end

    local target = playerIdResolve(player, targetArg)
    if not target then
        return
    end

    local targetAccountId = PlayerService.getAccountId(target)
    if not targetAccountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Gracz nie jest zalogowany na konto." })
        return
    end

    local nowSql = os.date("!%Y-%m-%d %H:%M:%S")
    LicenseBridge.call("findActiveSuspensions", { targetAccountId, category, nowSql }, function(ok, suspensionsOrError)
        if not ok or #suspensionsOrError == 0 then
            NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Gracz nie ma aktywnego zawieszenia tej kategorii." })
            return
        end

        local suspension = suspensionsOrError[1]
        LicenseBridge.call("revokeSuspension", { suspension.id }, function(revokeOk, affectedOrError)
            if not revokeOk then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zdjąć zawieszenia: " .. tostring(affectedOrError) })
                return
            end

            Logger.security("LicenseCommands", "License suspension revoked", {
                targetAccountId = targetAccountId,
                targetPlayer = getPlayerName(target),
                category = category,
                issuedBy = getPlayerName(player),
            })

            if isElement(target) then
                LicenseExamService.resyncElementData(target)
            end

            NotificationService.send(player, {
                type = Enums.NotificationType.SUCCESS,
                message = "Zdjęto zawieszenie kat. " .. category .. " gracza '" .. getPlayerName(target) .. "'.",
            })
        end)
    end)
end)
