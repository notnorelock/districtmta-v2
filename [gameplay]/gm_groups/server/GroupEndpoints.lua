-- Client -> server event handlers for the group management panel - each
-- one re-derives the requester's own membership/permission via
-- GroupBridge before doing anything, never trusts the panel's own belief
-- that an action is valid (mirrors gm_items/server/InventoryEndpoints.lua's
-- own module comment on the same reasoning). This project's gameplay
-- panels use plain Events (triggerServerEvent/triggerClientEvent +
-- uiPushEvent), not core_ui's FetchBridge - that's reserved for
-- core_auth's login/register flow, see AccountEndpoints.lua.
GroupEndpoints = GroupEndpoints or {}

--- @param permissions table decoded rank.permissions JSON object (or nil)
-- @param key string
-- @return boolean
local function hasPermission(permissions, key)
    return type(permissions) == "table" and (permissions.is_leader == true or permissions[key] == true)
end

--- @param member table a group_members row
-- @return table|nil a FRESH COPY of the member's own decoded permissions
--         (from their cached rank), or nil if they have no rank/the rank
--         isn't cached. Must be a copy, not the same table reference
--         GroupCache hands back for rank.permissions elsewhere (e.g.
--         toGroupEntry's own ranks[].permissions) - MTA's toJSON
--         deduplicates by TABLE IDENTITY: if the exact same table object
--         is reachable twice in one serialized structure (like sendMine's
--         { group = toGroupEntry(group) [which embeds rank.permissions],
--         member = ..., permissions = permissionsOf(member) }), the
--         second occurrence silently gets replaced with a "^T^N" table-
--         reference marker string instead of being serialized again -
--         confirmed live via outputServerLog (group.ranks[].permissions
--         serialized fine, the sibling top-level `permissions` came out
--         as "^T^5" garbage on the CEF side). A shallow copy is enough
--         since every permissions table is flat (key -> boolean only).
local function permissionsOf(member)
    if not member.rank_id then
        return nil
    end
    local rank = GroupCache.getRank(member.rank_id)
    if not rank or type(rank.permissions) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(rank.permissions) do
        copy[key] = value
    end
    return copy
end

--- @param accountId number
-- @param groupId number
-- @param callback function(member: table|nil)
local function findMembership(accountId, groupId, callback)
    GroupBridge.call("findMembersByAccountId", { accountId }, function(ok, membersOrError)
        if not ok then
            callback(nil)
            return
        end
        for _, member in ipairs(membersOrError) do
            if member.group_id == groupId then
                callback(member)
                return
            end
        end
        callback(nil)
    end)
end

--- @param accountId number
-- @return string|nil the currently-connected player's own name for this
--         account, or nil if they're offline right now - v1 has no
--         bridge to resolve an offline account's login (AccountRepository
--         isn't exposed to gm_groups), so an offline member's row falls
--         back to a placeholder client-side (see group.store.ts).
local function onlinePlayerNameForAccount(accountId)
    for _, player in ipairs(getElementsByType("player")) do
        if PlayerService.getAccountId(player) == accountId then
            return getPlayerName(player)
        end
    end
    return nil
end

--- @param member table a group_members row
-- @return table plain-data entry for the CEF panel
local function toMemberEntry(member)
    local rank = member.rank_id and GroupCache.getRank(member.rank_id)
    return {
        id = member.id,
        accountId = member.account_id,
        name = onlinePlayerNameForAccount(member.account_id),
        rankId = member.rank_id,
        rankName = rank and rank.name or nil,
        sortOrder = rank and rank.sort_order or nil,
        statWorkdutySeconds = member.stat_workduty_seconds or 0,
        lastPayoutAt = member.last_payout_at,
    }
end

--- @param group table cached group entry (GroupCache shape)
-- @return table plain-data entry for the CEF panel
local function toGroupEntry(group)
    local ranks = {}
    for _, rank in pairs(group.ranks) do
        ranks[#ranks + 1] = {
            id = rank.id,
            name = rank.name,
            skin = rank.skin,
            hourlyReward = rank.hourly_reward,
            permissions = rank.permissions,
            sortOrder = rank.sort_order,
        }
    end
    table.sort(ranks, function(a, b) return a.sortOrder < b.sortOrder end)

    return {
        id = group.id,
        name = group.name,
        type = group.type,
        color = group.color,
        hasDutyPosition = group.dutyPosition ~= nil,
        ranks = ranks,
    }
end

--- Sends `player` a fresh snapshot of every group they belong to. Exposed
--- on the GroupEndpoints table (not just a local) so GroupCommands.lua's
--- /creategroup can push fresh data right after creating a group/leader
--- rank/membership - every OTHER mutation in this file already refreshes
--- the panel via this same function post-reload, /creategroup is the one
--- mutation that happens outside this file entirely.
-- @param player element
local function sendMine(player)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    GroupBridge.call("findMembersByAccountId", { accountId }, function(ok, membersOrError)
        if not ok or not isElement(player) then
            return
        end

        local memberships = {}
        for _, member in ipairs(membersOrError) do
            local group = GroupCache.get(member.group_id)
            if group then
                memberships[#memberships + 1] = {
                    group = toGroupEntry(group),
                    member = toMemberEntry(member),
                    permissions = permissionsOf(member) or {},
                }
            end
        end

        triggerClientEvent(player, Events.GROUP_MINE_RECEIVED, resourceRoot, memberships)
    end)
end
GroupEndpoints.sendMine = sendMine

addEvent(Events.GROUP_REQUEST_MINE, true)
addEventHandler(Events.GROUP_REQUEST_MINE, root, function()
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end
    sendMine(client)
end)

--- Sends `player` the full roster of `groupId`, only if they're actually a
--- member of it - never trusts the panel's own belief that it's allowed
--- to browse an arbitrary group's members.
-- @param player element
-- @param groupId number
local function sendMembers(player, groupId)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    findMembership(accountId, groupId, function(requesterMember)
        if not requesterMember then
            return
        end

        GroupBridge.call("findMembersByGroupId", { groupId }, function(ok, membersOrError)
            if not ok or not isElement(player) then
                return
            end

            local entries = {}
            for _, member in ipairs(membersOrError) do
                entries[#entries + 1] = toMemberEntry(member)
            end

            triggerClientEvent(player, Events.GROUP_MEMBERS_RECEIVED, resourceRoot, { groupId = groupId, members = entries })
        end)
    end)
end

addEvent(Events.GROUP_REQUEST_MEMBERS, true)
addEventHandler(Events.GROUP_REQUEST_MEMBERS, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" then
        return
    end
    if getElementData(client, ElementData.Player.SPAWNED) ~= true then
        return
    end
    sendMembers(client, data.groupId)
end)

--- @param groupId number
-- @param player element
-- @param requiredKey string permission key required (or is_leader)
-- @param onOk function(member: table)
local function requirePermission(groupId, player, requiredKey, onOk)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    findMembership(accountId, groupId, function(member)
        if not member or not hasPermission(permissionsOf(member), requiredKey) then
            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie masz uprawnień do wykonania tej akcji." })
            end
            return
        end
        onOk(member)
    end)
end

addEvent(Events.GROUP_CREATE_RANK, true)
addEventHandler(Events.GROUP_CREATE_RANK, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" then
        return
    end
    local player = client

    requirePermission(data.groupId, player, "manage_ranks", function()
        GroupBridge.call("createRank", { {
            group_id = data.groupId,
            name = tostring(data.name or "Ranga"),
            skin = tonumber(data.skin) or 0,
            hourly_reward = tonumber(data.hourlyReward) or 0,
            permissions = type(data.permissions) == "table" and data.permissions or {},
            sort_order = tonumber(data.sortOrder) or 0,
        } }, function(ok, rankOrError)
            if not ok then
                Logger.error("GroupEndpoints", "Failed to create rank", { groupId = data.groupId, error = tostring(rankOrError) })
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się utworzyć rangi." })
                end
                return
            end

            GroupDutyService.reload(function()
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Utworzono rangę." })
                    sendMine(player)
                end
            end)
        end)
    end)
end)

addEvent(Events.GROUP_UPDATE_RANK, true)
addEventHandler(Events.GROUP_UPDATE_RANK, root, function(data)
    if type(data) ~= "table" or type(data.rankId) ~= "number" then
        return
    end
    local player = client

    local existingRank = GroupCache.getRank(data.rankId)
    if not existingRank then
        return
    end

    requirePermission(existingRank.group_id, player, "manage_ranks", function()
        GroupBridge.call("updateRank", { data.rankId, {
            name = data.name ~= nil and tostring(data.name) or existingRank.name,
            skin = data.skin ~= nil and tonumber(data.skin) or existingRank.skin,
            hourly_reward = data.hourlyReward ~= nil and tonumber(data.hourlyReward) or existingRank.hourly_reward,
            permissions = type(data.permissions) == "table" and data.permissions or existingRank.permissions,
            sort_order = data.sortOrder ~= nil and tonumber(data.sortOrder) or existingRank.sort_order,
        } }, function(ok, affectedOrError)
            if not ok then
                Logger.error("GroupEndpoints", "Failed to update rank", { rankId = data.rankId, error = tostring(affectedOrError) })
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zaktualizować rangi." })
                end
                return
            end

            GroupDutyService.reload(function()
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Zaktualizowano rangę." })
                    sendMine(player)
                end
            end)
        end)
    end)
end)

addEvent(Events.GROUP_DELETE_RANK, true)
addEventHandler(Events.GROUP_DELETE_RANK, root, function(data)
    if type(data) ~= "table" or type(data.rankId) ~= "number" then
        return
    end
    local player = client

    local existingRank = GroupCache.getRank(data.rankId)
    if not existingRank then
        return
    end
    local groupId = existingRank.group_id

    requirePermission(groupId, player, "manage_ranks", function()
        local group = GroupCache.get(groupId)
        local rankCount = group and (function()
            local count = 0
            for _ in pairs(group.ranks) do count = count + 1 end
            return count
        end)() or 0

        if rankCount <= 1 then
            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie można usunąć jedynej rangi w grupie." })
            end
            return
        end

        GroupBridge.call("findMembersByGroupId", { groupId }, function(membersOk, membersOrError)
            if not membersOk then
                return
            end
            for _, member in ipairs(membersOrError) do
                if member.rank_id == data.rankId then
                    if isElement(player) then
                        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Najpierw przenieś członków z tej rangi." })
                    end
                    return
                end
            end

            GroupBridge.call("deleteRank", { data.rankId }, function(ok, affectedOrError)
                if not ok then
                    Logger.error("GroupEndpoints", "Failed to delete rank", { rankId = data.rankId, error = tostring(affectedOrError) })
                    return
                end

                GroupDutyService.reload(function()
                    if isElement(player) then
                        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Usunięto rangę." })
                        sendMine(player)
                    end
                end)
            end)
        end)
    end)
end)

addEvent(Events.GROUP_ASSIGN_MEMBER_RANK, true)
addEventHandler(Events.GROUP_ASSIGN_MEMBER_RANK, root, function(data)
    if type(data) ~= "table" or type(data.memberId) ~= "number" or type(data.rankId) ~= "number" then
        return
    end
    local player = client

    GroupBridge.call("findMemberById", { data.memberId }, function(memberOk, targetMemberOrError)
        if not memberOk or not targetMemberOrError then
            return
        end
        local targetMember = targetMemberOrError

        local newRank = GroupCache.getRank(data.rankId)
        if not newRank or newRank.group_id ~= targetMember.group_id then
            return
        end

        requirePermission(targetMember.group_id, player, "manage_members", function(requesterMember)
            local requesterRank = requesterMember.rank_id and GroupCache.getRank(requesterMember.rank_id)
            local requesterSortOrder = requesterRank and requesterRank.sort_order or math.huge
            local currentTargetRank = targetMember.rank_id and GroupCache.getRank(targetMember.rank_id)
            local currentTargetSortOrder = currentTargetRank and currentTargetRank.sort_order or math.huge

            -- Requester must be strictly more senior (lower sort_order)
            -- than both the target's current rank and the rank being
            -- assigned - can't promote someone to/above your own level.
            if requesterSortOrder >= currentTargetSortOrder or requesterSortOrder >= newRank.sort_order then
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie możesz przydzielić tej rangi." })
                end
                return
            end

            GroupBridge.call("updateMember", { data.memberId, { rank_id = data.rankId } }, function(ok, affectedOrError)
                if not ok then
                    Logger.error("GroupEndpoints", "Failed to assign member rank", { memberId = data.memberId, error = tostring(affectedOrError) })
                    return
                end

                MembershipCache.set(targetMember.account_id, targetMember.group_id, data.rankId)

                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Przydzielono rangę." })
                    sendMine(player)
                    sendMembers(player, targetMember.group_id)
                end
            end)
        end)
    end)
end)

addEvent(Events.GROUP_KICK_MEMBER, true)
addEventHandler(Events.GROUP_KICK_MEMBER, root, function(data)
    if type(data) ~= "table" or type(data.memberId) ~= "number" then
        return
    end
    local player = client

    GroupBridge.call("findMemberById", { data.memberId }, function(memberOk, targetMemberOrError)
        if not memberOk or not targetMemberOrError then
            return
        end
        local targetMember = targetMemberOrError
        local group = GroupCache.get(targetMember.group_id)

        if group and group.leaderAccountId == targetMember.account_id then
            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie można wyrzucić lidera grupy." })
            end
            return
        end

        requirePermission(targetMember.group_id, player, "manage_members", function(requesterMember)
            local requesterRank = requesterMember.rank_id and GroupCache.getRank(requesterMember.rank_id)
            local requesterSortOrder = requesterRank and requesterRank.sort_order or math.huge
            local targetRank = targetMember.rank_id and GroupCache.getRank(targetMember.rank_id)
            local targetSortOrder = targetRank and targetRank.sort_order or math.huge

            if requesterSortOrder >= targetSortOrder and targetMember.account_id ~= PlayerService.getAccountId(player) then
                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie możesz wyrzucić tego członka." })
                end
                return
            end

            -- If the kicked member is currently online and on duty for
            -- this group, flush their session first.
            for _, target in ipairs(getElementsByType("player")) do
                if PlayerService.getAccountId(target) == targetMember.account_id then
                    local status = GroupDutyService.getMemberDutyStatus(target)
                    if status and status.groupId == targetMember.group_id then
                        GroupDutyService.exitDuty(target, "kicked_from_group")
                    end
                    break
                end
            end

            GroupBridge.call("deleteMember", { data.memberId }, function(ok, affectedOrError)
                if not ok then
                    Logger.error("GroupEndpoints", "Failed to kick member", { memberId = data.memberId, error = tostring(affectedOrError) })
                    return
                end

                MembershipCache.remove(targetMember.account_id, targetMember.group_id)

                if isElement(player) then
                    NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Usunięto członka z grupy." })
                    sendMine(player)
                    sendMembers(player, targetMember.group_id)
                end
            end)
        end)
    end)
end)

addEvent(Events.GROUP_LEAVE, true)
addEventHandler(Events.GROUP_LEAVE, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" then
        return
    end
    local player = client
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    local group = GroupCache.get(data.groupId)
    if group and group.leaderAccountId == accountId then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Lider musi najpierw przekazać przywództwo." })
        return
    end

    findMembership(accountId, data.groupId, function(member)
        if not member then
            return
        end

        local status = GroupDutyService.getMemberDutyStatus(player)
        if status and status.groupId == data.groupId then
            GroupDutyService.exitDuty(player, "left_group")
        end

        GroupBridge.call("deleteMember", { member.id }, function(ok, affectedOrError)
            if not ok then
                Logger.error("GroupEndpoints", "Failed to leave group", { memberId = member.id, error = tostring(affectedOrError) })
                return
            end

            MembershipCache.remove(accountId, data.groupId)

            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Opuszczono grupę." })
                sendMine(player)
            end
        end)
    end)
end)

addEvent(Events.GROUP_REQUEST_INVITABLE_PLAYERS, true)
addEventHandler(Events.GROUP_REQUEST_INVITABLE_PLAYERS, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" then
        return
    end
    local player = client
    local groupId = data.groupId

    requirePermission(groupId, player, "manage_members", function()
        GroupBridge.call("findMembersByGroupId", { groupId }, function(membersOk, membersOrError)
            if not membersOk or not isElement(player) then
                return
            end

            local existingAccountIds = {}
            for _, member in ipairs(membersOrError) do
                existingAccountIds[member.account_id] = true
            end

            GroupBridge.call("findInvitesByGroupId", { groupId }, function(invitesOk, invitesOrError)
                if not invitesOk or not isElement(player) then
                    return
                end

                local pendingAccountIds = {}
                for _, invite in ipairs(invitesOrError) do
                    pendingAccountIds[invite.account_id] = true
                end

                local players = {}
                for _, target in ipairs(getElementsByType("player")) do
                    local targetAccountId = PlayerService.getAccountId(target)
                    if targetAccountId and not existingAccountIds[targetAccountId] and not pendingAccountIds[targetAccountId] then
                        players[#players + 1] = { accountId = targetAccountId, name = getPlayerName(target) }
                    end
                end

                triggerClientEvent(player, Events.GROUP_INVITABLE_PLAYERS_RECEIVED, resourceRoot, { groupId = groupId, players = players })
            end)
        end)
    end)
end)

addEvent(Events.GROUP_INVITE_PLAYER, true)
addEventHandler(Events.GROUP_INVITE_PLAYER, root, function(data)
    if type(data) ~= "table" or type(data.groupId) ~= "number" or type(data.accountId) ~= "number" then
        return
    end
    local player = client
    local groupId = data.groupId
    local targetAccountId = data.accountId

    requirePermission(groupId, player, "manage_members", function(requesterMember)
        local group = GroupCache.get(groupId)
        if not group then
            return
        end

        local targetPlayer = nil
        for _, candidate in ipairs(getElementsByType("player")) do
            if PlayerService.getAccountId(candidate) == targetAccountId then
                targetPlayer = candidate
                break
            end
        end
        if not targetPlayer then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Ten gracz nie jest już online." })
            return
        end

        findMembership(targetAccountId, groupId, function(existingMember)
            if existingMember then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Ten gracz już należy do grupy." })
                return
            end

            GroupBridge.call("findInvitesByGroupId", { groupId }, function(invitesOk, invitesOrError)
                if not invitesOk then
                    return
                end
                for _, invite in ipairs(invitesOrError) do
                    if invite.account_id == targetAccountId then
                        if isElement(player) then
                            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Ten gracz ma już oczekujące zaproszenie." })
                        end
                        return
                    end
                end

                local requesterAccountId = PlayerService.getAccountId(player)
                GroupBridge.call("createInvite", { {
                    group_id = groupId,
                    account_id = targetAccountId,
                    invited_by_account_id = requesterAccountId,
                } }, function(ok, inviteOrError)
                    if not ok then
                        Logger.error("GroupEndpoints", "Failed to create invite", { groupId = groupId, targetAccountId = targetAccountId, error = tostring(inviteOrError) })
                        return
                    end
                    local invite = inviteOrError

                    if isElement(player) then
                        NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Wysłano zaproszenie." })
                    end

                    if isElement(targetPlayer) then
                        triggerClientEvent(targetPlayer, Events.GROUP_INVITE_RECEIVED, resourceRoot, {
                            inviteId = invite.id,
                            groupId = group.id,
                            groupName = group.name,
                            groupType = group.type,
                            invitedByName = getPlayerName(player),
                        })
                    end
                end)
            end)
        end)
    end)
end)

--- @param invite table a group_invites row
-- @return table plain-data entry for the CEF invite prompt/list
local function toInviteEntry(invite)
    local group = GroupCache.get(invite.group_id)
    return {
        inviteId = invite.id,
        groupId = invite.group_id,
        groupName = group and group.name or "?",
        groupType = group and group.type or "organization",
        invitedByName = onlinePlayerNameForAccount(invite.invited_by_account_id) or "?",
    }
end

addEvent(Events.GROUP_REQUEST_INVITES, true)
addEventHandler(Events.GROUP_REQUEST_INVITES, root, function()
    local player = client
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    GroupBridge.call("findInvitesByAccountId", { accountId }, function(ok, invitesOrError)
        if not ok or not isElement(player) then
            return
        end

        local entries = {}
        for _, invite in ipairs(invitesOrError) do
            entries[#entries + 1] = toInviteEntry(invite)
        end

        triggerClientEvent(player, Events.GROUP_INVITES_RECEIVED, resourceRoot, entries)
    end)
end)

addEvent(Events.GROUP_ACCEPT_INVITE, true)
addEventHandler(Events.GROUP_ACCEPT_INVITE, root, function(data)
    if type(data) ~= "table" or type(data.inviteId) ~= "number" then
        return
    end
    local player = client
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    GroupBridge.call("findInviteById", { data.inviteId }, function(ok, inviteOrError)
        if not ok or not inviteOrError then
            return
        end
        local invite = inviteOrError

        -- Never trust the client's own belief this invite is theirs.
        if invite.account_id ~= accountId then
            if isElement(player) then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "To zaproszenie nie jest dla Ciebie." })
            end
            return
        end

        -- rank_id deliberately omitted (not set to nil - an omitted Lua
        -- table key and one explicitly set to nil are indistinguishable
        -- anyway) - a rankless member, same "leader assigns a rank later"
        -- state as any other freshly-added member the leader hasn't
        -- ranked yet (see GroupDutyService.lua's own enterDuty rejecting
        -- a nil-rank member from entering duty).
        GroupBridge.call("createMember", { {
            group_id = invite.group_id,
            account_id = accountId,
        } }, function(memberOk, memberOrError)
            if not memberOk then
                Logger.error("GroupEndpoints", "Failed to accept invite", { inviteId = data.inviteId, error = tostring(memberOrError) })
                return
            end

            GroupBridge.call("deleteInvite", { data.inviteId }, function() end)

            MembershipCache.set(accountId, invite.group_id, nil)

            if isElement(player) then
                local group = GroupCache.get(invite.group_id)
                NotificationService.send(player, { type = Enums.NotificationType.SUCCESS, message = "Dołączono do grupy: " .. (group and group.name or "") })
                sendMine(player)
            end
        end)
    end)
end)

addEvent(Events.GROUP_DECLINE_INVITE, true)
addEventHandler(Events.GROUP_DECLINE_INVITE, root, function(data)
    if type(data) ~= "table" or type(data.inviteId) ~= "number" then
        return
    end
    local player = client
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    GroupBridge.call("findInviteById", { data.inviteId }, function(ok, inviteOrError)
        if not ok or not inviteOrError then
            return
        end
        local invite = inviteOrError

        -- Allow either the invitee declining their own invite, or a
        -- manage_members member of the target group revoking it.
        if invite.account_id == accountId then
            GroupBridge.call("deleteInvite", { data.inviteId }, function() end)
            return
        end

        requirePermission(invite.group_id, player, "manage_members", function()
            GroupBridge.call("deleteInvite", { data.inviteId }, function() end)
        end)
    end)
end)
