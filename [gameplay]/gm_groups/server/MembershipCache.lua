-- Lightweight in-memory cache of WHO belongs to WHICH group at WHAT rank
-- (accountId -> { [groupId] = rankId|nil }) - exists purely so
-- GroupVehicleService.lua's groupServiceCanUseVehicle export can answer
-- synchronously (a cross-resource MTA export must return immediately, no
-- callback/DB round trip possible - see VehicleInteractionService.lua's
-- own canStartEngine, which needs a same-frame true/false to gate engine
-- start). Deliberately SEPARATE from GroupCache.lua's own explicit
-- "never cache members, they're money-adjacent" stance (see that file's
-- own module comment) - membership/rank identity itself is cheap to lose
-- and reload (a stale read here only risks a moment of wrong vehicle
-- access, never a lost payout or lost duty time), unlike stat_workduty_seconds.
--
-- Reloaded in full on resource start (alongside GroupCache.reload) and
-- patched incrementally by GroupEndpoints.lua on every membership-
-- affecting mutation (invite accept, rank assign, kick, leave) - see this
-- file's own update/remove functions, called from those handlers.
MembershipCache = MembershipCache or {}

-- accountId -> { [groupId] = rankId | false }
-- false = a member with no rank assigned yet (distinct from "key absent",
-- which means "not a member of this group at all") - Lua tables can't
-- hold a real nil value as "present", so a rankless member is stored as
-- the boolean false instead, same sentinel trick used elsewhere in this
-- project's cache tables.
local memberships = {}

--- Clears and rebuilds the whole cache from the database - every group's
--- full member list, one bridge call per group (mirrors GroupCache.reload's
--- own per-group fan-out pattern).
-- @param callback function()|nil
MembershipCache.reload = function(callback)
    memberships = {}

    local groups = GroupCache.all()
    local groupIds = {}
    for groupId in pairs(groups) do
        groupIds[#groupIds + 1] = groupId
    end

    local pending = #groupIds
    if pending == 0 then
        if callback then callback() end
        return
    end

    for _, groupId in ipairs(groupIds) do
        GroupBridge.call("findMembersByGroupId", { groupId }, function(ok, membersOrError)
            if ok then
                for _, member in ipairs(membersOrError) do
                    memberships[member.account_id] = memberships[member.account_id] or {}
                    memberships[member.account_id][groupId] = member.rank_id or false
                end
            else
                Logger.error("MembershipCache", "Failed to load members for group", { groupId = groupId, error = tostring(membersOrError) })
            end

            pending = pending - 1
            if pending <= 0 and callback then
                callback()
            end
        end)
    end
end

--- @param accountId number
-- @param groupId number
-- @param rankId number|nil nil = rankless member
MembershipCache.set = function(accountId, groupId, rankId)
    memberships[accountId] = memberships[accountId] or {}
    memberships[accountId][groupId] = rankId or false
end

--- @param accountId number
-- @param groupId number
MembershipCache.remove = function(accountId, groupId)
    if memberships[accountId] then
        memberships[accountId][groupId] = nil
    end
end

--- @param accountId number
-- @param groupId number
-- @return boolean, number|nil isMember, rankId (nil if isMember is true but no rank assigned yet)
MembershipCache.get = function(accountId, groupId)
    local byGroup = memberships[accountId]
    if not byGroup or byGroup[groupId] == nil then
        return false, nil
    end
    local rankId = byGroup[groupId]
    return true, rankId ~= false and rankId or nil
end
