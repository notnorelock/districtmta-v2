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

-- groupId -> { id, name, type, color, leaderAccountId, dutyPosition,
-- ranks = { [rankId] = rankRow },
-- vehicles = { [vehicleId] = vehicleRow },
-- vehicleRankAllowlist = { [vehicleId] = { [rankId] = true } } }
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

        -- Each group has TWO independent sub-loads (ranks, vehicles+their
        -- allowlists) that must both finish before this group counts as
        -- done - pending counts groups, not sub-loads, so a group is only
        -- decremented once both its own sub-loads have completed (see
        -- awaitGroupDone below).
        for _, groupRow in ipairs(groupsOrError) do
            local entry = {
                id = groupRow.id,
                name = groupRow.name,
                type = groupRow.type,
                color = groupRow.color,
                leaderAccountId = groupRow.leader_account_id,
                dutyPosition = groupRow.duty_position,
                ranks = {},
                vehicles = {},
                vehicleRankAllowlist = {},
            }
            groups[entry.id] = entry

            local groupSubLoadsRemaining = 2
            local function onGroupSubLoadDone()
                groupSubLoadsRemaining = groupSubLoadsRemaining - 1
                if groupSubLoadsRemaining > 0 then
                    return
                end

                pending = pending - 1
                if pending <= 0 then
                    Logger.info("GroupCache", "Loaded groups", { count = #groupsOrError })
                    if callback then callback() end
                end
            end

            GroupBridge.call("findRanksByGroupId", { entry.id }, function(rankOk, ranksOrError)
                if rankOk then
                    for _, rankRow in ipairs(ranksOrError) do
                        entry.ranks[rankRow.id] = rankRow
                    end
                else
                    Logger.error("GroupCache", "Failed to load ranks for group", { groupId = entry.id, error = tostring(ranksOrError) })
                end
                onGroupSubLoadDone()
            end)

            GroupVehicleBridge.call("findByGroupId", { entry.id }, function(vehiclesOk, vehiclesOrError)
                if not vehiclesOk then
                    Logger.error("GroupCache", "Failed to load vehicles for group", { groupId = entry.id, error = tostring(vehiclesOrError) })
                    onGroupSubLoadDone()
                    return
                end

                local vehicleRows = vehiclesOrError
                for _, vehicleRow in ipairs(vehicleRows) do
                    entry.vehicles[vehicleRow.id] = vehicleRow
                end

                local vehiclesPending = #vehicleRows
                if vehiclesPending == 0 then
                    onGroupSubLoadDone()
                    return
                end

                for _, vehicleRow in ipairs(vehicleRows) do
                    GroupVehicleBridge.call("findVehicleRanksByVehicleId", { vehicleRow.id }, function(ranksOk, allowlistOrError)
                        if ranksOk then
                            local allowlist = {}
                            for _, allowRow in ipairs(allowlistOrError) do
                                allowlist[allowRow.rank_id] = true
                            end
                            entry.vehicleRankAllowlist[vehicleRow.id] = allowlist
                        else
                            Logger.error("GroupCache", "Failed to load vehicle rank allowlist", { vehicleId = vehicleRow.id, error = tostring(allowlistOrError) })
                        end

                        vehiclesPending = vehiclesPending - 1
                        if vehiclesPending <= 0 then
                            onGroupSubLoadDone()
                        end
                    end)
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

--- @param vehicleId number
-- @return table|nil { group = groupEntry, vehicle = vehicleRow, allowlist = { [rankId] = true } },
--         searched across every group - nil if this vehicle id isn't a
--         currently-known group vehicle.
GroupCache.getVehicle = function(vehicleId)
    for _, group in pairs(groups) do
        local vehicle = group.vehicles[vehicleId]
        if vehicle then
            return {
                group = group,
                vehicle = vehicle,
                allowlist = group.vehicleRankAllowlist[vehicleId] or {},
            }
        end
    end
    return nil
end

--- Re-fetches just ONE group's own vehicles + their rank allowlists,
--- in place on its existing cache entry - cheap alternative to a full
--- GroupCache.reload() for "a new group vehicle was just created"
--- (gm_vehicles' own /creategroupvehicle) - see GroupVehicleService.lua's
--- groupServiceReloadVehicles export, the only caller.
-- @param groupId number
-- @param callback function()|nil
GroupCache.reloadVehiclesForGroup = function(groupId, callback)
    local group = groups[groupId]
    if not group then
        if callback then callback() end
        return
    end

    GroupVehicleBridge.call("findByGroupId", { groupId }, function(ok, vehiclesOrError)
        if not ok then
            Logger.error("GroupCache", "Failed to reload vehicles for group", { groupId = groupId, error = tostring(vehiclesOrError) })
            if callback then callback() end
            return
        end

        group.vehicles = {}
        group.vehicleRankAllowlist = {}

        local vehicleRows = vehiclesOrError
        for _, vehicleRow in ipairs(vehicleRows) do
            group.vehicles[vehicleRow.id] = vehicleRow
        end

        local pending = #vehicleRows
        if pending == 0 then
            if callback then callback() end
            return
        end

        for _, vehicleRow in ipairs(vehicleRows) do
            GroupVehicleBridge.call("findVehicleRanksByVehicleId", { vehicleRow.id }, function(ranksOk, allowlistOrError)
                if ranksOk then
                    local allowlist = {}
                    for _, allowRow in ipairs(allowlistOrError) do
                        allowlist[allowRow.rank_id] = true
                    end
                    group.vehicleRankAllowlist[vehicleRow.id] = allowlist
                else
                    Logger.error("GroupCache", "Failed to reload vehicle rank allowlist", { vehicleId = vehicleRow.id, error = tostring(allowlistOrError) })
                end

                pending = pending - 1
                if pending <= 0 and callback then
                    callback()
                end
            end)
        end
    end)
end
