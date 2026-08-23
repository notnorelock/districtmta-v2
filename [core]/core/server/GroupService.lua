-- Server-to-server bridge exposing GroupRepository/GroupRankRepository/
-- GroupMemberRepository to gm_groups (a separate resource) without ever
-- handing a callback across the resource boundary - see
-- GroupRepository.lua's own module comment and docs/Architecture.md's
-- "The one hard rule for extending the project". Mirrors VehicleService.lua's
-- own requestId-correlated request/response shape exactly: gm_groups/
-- server/GroupBridge.lua triggers Events.GROUP_REPOSITORY_REQUEST with
-- { requestId, method, args }, this file runs the matching repository
-- method locally (the callback closure never leaves this resource) and
-- triggers Events.GROUP_REPOSITORY_RESPONSE back with { requestId, ok, result }.
GroupService = GroupService or {}

-- Whitelist, not a raw _G[method] lookup - see VehicleService.lua's own
-- comment on why. Method names are prefixed per-entity (findGroupById vs
-- findRankById vs findMemberById) since this one flat table covers three
-- separate repositories, unlike VehicleService.lua's own METHODS where
-- "findById" only ever meant one thing.
local METHODS = {
    -- Group
    findGroupById = GroupRepository.findById,
    findAllGroups = GroupRepository.findAll,
    findGroupByLeaderAccountId = GroupRepository.findByLeaderAccountId,
    createGroup = GroupRepository.create,
    updateGroup = GroupRepository.update,
    deleteGroup = GroupRepository.delete,

    -- GroupRank
    findRankById = GroupRankRepository.findById,
    findRanksByGroupId = GroupRankRepository.findByGroupId,
    createRank = GroupRankRepository.create,
    updateRank = GroupRankRepository.update,
    deleteRank = GroupRankRepository.delete,

    -- GroupMember
    findMemberById = GroupMemberRepository.findById,
    findMembersByGroupId = GroupMemberRepository.findByGroupId,
    findMembersByAccountId = GroupMemberRepository.findByAccountId,
    createMember = GroupMemberRepository.create,
    updateMember = GroupMemberRepository.update,
    deleteMember = GroupMemberRepository.delete,
    incrementMemberDutySeconds = GroupMemberRepository.incrementDutySeconds,
    payoutMember = GroupMemberRepository.payout,

    -- GroupInvite
    findInviteById = GroupInviteRepository.findById,
    findInvitesByAccountId = GroupInviteRepository.findByAccountId,
    findInvitesByGroupId = GroupInviteRepository.findByGroupId,
    createInvite = GroupInviteRepository.create,
    deleteInvite = GroupInviteRepository.delete,
}

addEvent(Events.GROUP_REPOSITORY_REQUEST, true)
addEventHandler(Events.GROUP_REPOSITORY_REQUEST, root, function(data)
    if type(data) ~= "table" or type(data.requestId) ~= "string" or type(data.method) ~= "string" then
        Logger.warn("GroupService", "Malformed GROUP_REPOSITORY_REQUEST", { data = data })
        return
    end

    local method = METHODS[data.method]
    if not method then
        Logger.warn("GroupService", "Unknown group repository method requested", { method = data.method })
        triggerEvent(Events.GROUP_REPOSITORY_RESPONSE, resourceRoot, data.requestId, false, "UNKNOWN_METHOD")
        return
    end

    local args = data.args or {}

    -- Every method here takes 0-2 positional arguments before its
    -- callback (id/groupId/accountId/attributes, or (id, seconds) for
    -- incrementMemberDutySeconds) - args is always an array, positionally matching.
    local function respond(ok, result)
        triggerEvent(Events.GROUP_REPOSITORY_RESPONSE, resourceRoot, data.requestId, ok, result)
    end

    if #args == 0 then
        method(respond)
    elseif #args == 1 then
        method(args[1], respond)
    else
        method(args[1], args[2], respond)
    end
end)

-- schemaIsMigrated is already exported once (VehicleService.lua) - reused
-- as-is, no new export needed here.
