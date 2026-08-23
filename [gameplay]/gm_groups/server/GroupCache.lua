-- In-memory cache of structural, rarely-changing group data (group +
-- rank rows: name, type, color, duty position, per-rank skin/hourly
-- reward/permissions/sort_order) - reloaded from the database on
-- resource start and again any time GroupEndpoints.lua mutates a
-- group/rank, so GroupDutyService.lua's duty-enter skin lookup and marker
-- rebuild never see stale data.
--
-- Deliberately does NOT cache member rows or accrued duty seconds -
-- those stay DB-authoritative at all times (read/written fresh through
-- GroupBridge on every use), since duty seconds are money-adjacent state
-- that must survive this resource crashing/restarting without loss. An
-- earlier, unrelated reference implementation this project's group system
-- was adapted from cached everything (including live duty accrual) in one
-- big table - deliberately not repeated here.
GroupCache = GroupCache or {}

-- groupId -> { id, name, type, color, leaderAccountId, dutyPosition, ranks = { [rankId] = rankRow } }
local groups = {}

--- Clears and rebuilds the cache from the database (all groups, then each
--- group's own ranks). Does not touch anything member/duty-session
--- related - callers that also need markers rebuilt (GroupDutyService.lua)
--- call this first, then rebuild markers from the freshly-loaded cache.
-- @param callback function()|nil called once the reload finishes
GroupCache.reload = function(callback)
    groups = {}

    GroupBridge.call("findAllGroups", {}, function(ok, groupsOrError)
        if not ok then
            Logger.error("GroupCache", "Failed to load groups", { error = tostring(groupsOrError) })
            if callback then callback() end
            return
        end

        local pending = #groupsOrError
        if pending == 0 then
            Logger.info("GroupCache", "Loaded groups", { count = 0 })
            if callback then callback() end
            return
        end

        for _, groupRow in ipairs(groupsOrError) do
            local entry = {
                id = groupRow.id,
                name = groupRow.name,
                type = groupRow.type,
                color = groupRow.color,
                leaderAccountId = groupRow.leader_account_id,
                dutyPosition = groupRow.duty_position,
                ranks = {},
            }
            groups[entry.id] = entry

            GroupBridge.call("findRanksByGroupId", { entry.id }, function(rankOk, ranksOrError)
                if rankOk then
                    for _, rankRow in ipairs(ranksOrError) do
                        entry.ranks[rankRow.id] = rankRow
                    end
                else
                    Logger.error("GroupCache", "Failed to load ranks for group", { groupId = entry.id, error = tostring(ranksOrError) })
                end

                pending = pending - 1
                if pending <= 0 then
                    Logger.info("GroupCache", "Loaded groups", { count = #groupsOrError })
                    if callback then callback() end
                end
            end)
        end
    end)
end

--- @param groupId number
-- @return table|nil the cached group entry (id/name/type/color/leaderAccountId/dutyPosition/ranks)
GroupCache.get = function(groupId)
    return groups[groupId]
end

--- @param rankId number
-- @return table|nil the cached rank row, searched across every group
GroupCache.getRank = function(rankId)
    for _, group in pairs(groups) do
        local rank = group.ranks[rankId]
        if rank then
            return rank
        end
    end
    return nil
end

--- @return table groupId -> group entry, for iterating during marker (re)creation
GroupCache.all = function()
    return groups
end
