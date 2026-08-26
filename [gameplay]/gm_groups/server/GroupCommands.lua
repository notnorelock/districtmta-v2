-- Admin/leader commands for the groups system:
-- /creategroup <name> <gang|organization|fraction> - admin-only (MANAGE_GROUPS),
--   creates the group with the issuing admin as leader + an initial "Lider"
--   rank (is_leader permission, sort_order 0) and enrolls them as its first member.
-- /deletegroup <name> - admin-only, cascades ranks -> members -> group row
--   in sequence (this ORM has no ON DELETE CASCADE, see GroupRepository.lua's
--   own comment on GroupRepository.delete).
-- /setgroupduty <name> - admin OR a member with is_leader/manage_ranks,
--   sets duty_position to the issuer's current position, reloads GroupDutyService.
-- /dutypayout - pays out accrued on-duty time at the member's current
--   rank's hourly rate, gated on a 2h minimum and a 24h cooldown.

--- @param player element
-- @return boolean
local function isReady(player)
    return exports.core_shared:isPlayerReady(player)
end

--- @param player element
-- @return boolean
local function canManageGroups(player)
    local role = PlayerService.getRole(player)
    if role == nil then
        return false
    end
    return Permissions.has(role, Permissions.Bit.MANAGE_GROUPS) == true
end

--- @param typeArg string|nil
-- @return string|nil "gang"|"organization"|"fraction", or nil if invalid
local function parseGroupType(typeArg)
    local value = tostring(typeArg or ""):lower()
    if value == "gang" or value == "organization" or value == "fraction" then
        return value
    end
    return nil
end

addCommandHandler("creategroup", function(player, _, nameArg, typeArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if not canManageGroups(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    local name = tostring(nameArg or "")
    local groupType = parseGroupType(typeArg)
    if name == "" or not groupType then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /creategroup <nazwa> <gang|organization|fraction>" })
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się ustalić Twojego konta." })
        return
    end

    GroupBridge.call("createGroup", { {
        name = name,
        type = groupType,
        leader_account_id = accountId,
    } }, function(ok, groupOrError)
        if not ok then
            Logger.error("GroupCommands", "Failed to create group", { name = name, error = tostring(groupOrError) })
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się utworzyć grupy (nazwa zajęta?)." })
            return
        end
        local group = groupOrError

        GroupBridge.call("createRank", { {
            group_id = group.id,
            name = "Lider",
            skin = getElementModel(player),
            hourly_reward = 0,
            permissions = { is_leader = true },
            sort_order = 0,
        } }, function(rankOk, rankOrError)
            if not rankOk then
                Logger.error("GroupCommands", "Failed to create leader rank", { groupId = group.id, error = tostring(rankOrError) })
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Grupa utworzona, ale nie udało się utworzyć rangi lidera." })
                return
            end
            local rank = rankOrError

            GroupBridge.call("createMember", { {
                group_id = group.id,
                account_id = accountId,
                rank_id = rank.id,
            } }, function(memberOk, memberOrError)
                if not memberOk then
                    Logger.error("GroupCommands", "Failed to enroll leader as member", { groupId = group.id, error = tostring(memberOrError) })
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Grupa utworzona, ale nie udało się dodać Cię jako członka." })
                    return
                end

                GroupDutyService.reload(function()
                    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Utworzono grupę: " .. name })
                    Logger.security("GroupCommands", "Group created", { player = getPlayerName(player), groupId = group.id, name = name, type = groupType })
                    -- Refresh the issuing admin's own panel data (their
                    -- new leader membership/permissions) - every OTHER
                    -- group mutation does this via GroupEndpoints.lua's
                    -- own sendMine after its reload, this is the one
                    -- mutation that happens outside that file entirely.
                    if isElement(player) then
                        GroupEndpoints.sendMine(player)
                    end
                end)
            end)
        end)
    end)
end)

addCommandHandler("deletegroup", function(player, _, nameArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    if not canManageGroups(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
        return
    end

    local name = tostring(nameArg or "")
    if name == "" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /deletegroup <nazwa>" })
        return
    end

    local targetGroup = nil
    for _, group in pairs(GroupCache.all()) do
        if group.name == name then
            targetGroup = group
            break
        end
    end

    if not targetGroup then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie znaleziono grupy o takiej nazwie." })
        return
    end

    GroupBridge.call("findMembersByGroupId", { targetGroup.id }, function(membersOk, membersOrError)
        if not membersOk then
            Logger.error("GroupCommands", "Failed to load members for delete", { groupId = targetGroup.id, error = tostring(membersOrError) })
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się usunąć grupy." })
            return
        end

        local pendingMembers = #membersOrError
        local function afterMembersDeleted()
            local rankIds = {}
            for rankId in pairs(targetGroup.ranks) do
                rankIds[#rankIds + 1] = rankId
            end

            local pendingRanks = #rankIds
            local function afterRanksDeleted()
                GroupBridge.call("deleteGroup", { targetGroup.id }, function(ok, affectedOrError)
                    if not ok then
                        Logger.error("GroupCommands", "Failed to delete group row", { groupId = targetGroup.id, error = tostring(affectedOrError) })
                        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się usunąć grupy." })
                        return
                    end

                    -- Flush/kick anyone currently on duty for this group before the reload tears its marker down.
                    for _, target in ipairs(getElementsByType("player")) do
                        local status = GroupDutyService.getMemberDutyStatus(target)
                        if status and status.groupId == targetGroup.id then
                            GroupDutyService.exitDuty(target, "group_deleted")
                        end
                    end

                    GroupDutyService.reload(function()
                        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Usunięto grupę: " .. name })
                        Logger.security("GroupCommands", "Group deleted", { player = getPlayerName(player), groupId = targetGroup.id, name = name })
                    end)
                end)
            end

            if pendingRanks == 0 then
                afterRanksDeleted()
                return
            end
            for _, rankId in ipairs(rankIds) do
                GroupBridge.call("deleteRank", { rankId }, function()
                    pendingRanks = pendingRanks - 1
                    if pendingRanks <= 0 then
                        afterRanksDeleted()
                    end
                end)
            end
        end

        if pendingMembers == 0 then
            afterMembersDeleted()
            return
        end
        for _, member in ipairs(membersOrError) do
            GroupBridge.call("deleteMember", { member.id }, function()
                pendingMembers = pendingMembers - 1
                if pendingMembers <= 0 then
                    afterMembersDeleted()
                end
            end)
        end
    end)
end)

addCommandHandler("setgroupduty", function(player, _, nameArg)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    local name = tostring(nameArg or "")
    if name == "" then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Użycie: /setgroupduty <nazwa>" })
        return
    end

    local targetGroup = nil
    for _, group in pairs(GroupCache.all()) do
        if group.name == name then
            targetGroup = group
            break
        end
    end

    if not targetGroup then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie znaleziono grupy o takiej nazwie." })
        return
    end

    local function applyDutyPosition()
        local x, y, z = getElementPosition(player)
        local position = {
            x = x,
            y = y,
            z = z,
            interior = getElementInterior(player),
            dimension = getElementDimension(player),
        }

        GroupBridge.call("updateGroup", { targetGroup.id, { duty_position = position } }, function(ok, affectedOrError)
            if not ok then
                Logger.error("GroupCommands", "Failed to set duty position", { groupId = targetGroup.id, error = tostring(affectedOrError) })
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się ustawić punktu służby." })
                return
            end

            GroupDutyService.reload(function()
                NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Ustawiono punkt służby dla: " .. name })
                Logger.security("GroupCommands", "Group duty position set", { player = getPlayerName(player), groupId = targetGroup.id, name = name })
            end)
        end)
    end

    if canManageGroups(player) then
        applyDutyPosition()
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się ustalić Twojego konta." })
        return
    end

    GroupBridge.call("findMembersByGroupId", { targetGroup.id }, function(ok, membersOrError)
        if not ok then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zweryfikować członkostwa." })
            return
        end

        for _, member in ipairs(membersOrError) do
            if member.account_id == accountId then
                local rank = member.rank_id and GroupCache.getRank(member.rank_id)
                local permissions = rank and rank.permissions
                local allowed = type(permissions) == "table" and (permissions.is_leader == true or permissions.manage_ranks == true)
                if allowed then
                    applyDutyPosition()
                else
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do tej komendy." })
                end
                return
            end
        end

        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie należysz do tej grupy." })
    end)
end)

-- Minimum accrued on-duty time before a payout is allowed - carried
-- forward from the reference implementation this system was adapted from.
local MIN_PAYOUT_SECONDS = 2 * 3600
-- Cooldown between payouts, in seconds.
local PAYOUT_COOLDOWN_SECONDS = 24 * 3600

--- @param isoTimestamp string "YYYY-MM-DD HH:MM:SS" (UTC) - same shape as
--        AdminDutyStatsService.lua's own parseSqlTimestamp helper.
-- @return number unix seconds
local function parseSqlTimestamp(isoTimestamp)
    local year, month, day, hour, min, sec = isoTimestamp:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    return os.time({
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec),
    })
end

addCommandHandler("dutypayout", function(player)
    if not isElement(player) then
        return
    end

    if not isReady(player) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz być zalogowany i w grze, aby użyć tej komendy." })
        return
    end

    local status = GroupDutyService.getMemberDutyStatus(player)
    if not status then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie jesteś obecnie na służbie." })
        return
    end

    GroupBridge.call("findMemberById", { status.memberId }, function(ok, memberOrError)
        if not ok or not memberOrError then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się pobrać danych członkostwa." })
            return
        end
        local member = memberOrError

        local rank = GroupCache.getRank(status.rankId)
        if not rank or not rank.hourly_reward or rank.hourly_reward <= 0 then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Twoja ranga nie ma wypłaty za służbę." })
            return
        end

        local seconds = member.stat_workduty_seconds or 0
        if seconds < MIN_PAYOUT_SECONDS then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Musisz przepracować co najmniej 2 godziny, aby odebrać wypłatę." })
            return
        end

        if type(member.last_payout_at) == "string" then
            local lastPayout = parseSqlTimestamp(member.last_payout_at)
            if (os.time() - lastPayout) < PAYOUT_COOLDOWN_SECONDS then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Możesz odebrać wypłatę raz na 24 godziny." })
                return
            end
        end

        local cost = math.floor((seconds / 3600) * rank.hourly_reward)
        if cost <= 0 then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Brak środków do wypłaty." })
            return
        end

        GroupBridge.call("payoutMember", { member.id }, function(payoutOk, payoutErr)
            if not payoutOk then
                Logger.error("GroupCommands", "Failed to record payout", { memberId = member.id, error = tostring(payoutErr) })
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się przetworzyć wypłaty." })
                return
            end

            PlayerService.giveMoney(player, cost)
            NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Otrzymujesz wypłatę: $" .. cost })

            Logger.security("GroupCommands", "Duty payout", {
                player = getPlayerName(player),
                groupId = status.groupId,
                memberId = member.id,
                seconds = seconds,
                cost = cost,
            })
        end)
    end)
end)
