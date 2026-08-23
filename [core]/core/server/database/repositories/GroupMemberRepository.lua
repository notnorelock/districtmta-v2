-- Thin facade over the GroupMember Active Record model - mirrors
-- VehicleRepository.lua's own shape/conventions. No JSON columns (all
-- plain scalars). incrementDutySeconds/payout are atomic single-UPDATE
-- calls, not read-then-write, following AccountRepository.giveMoney's own
-- pattern - avoids losing accrued duty time to a race between two
-- concurrent ticks/payouts for the same member.
GroupMemberRepository = GroupMemberRepository or {}

--- @param id number
-- @param callback function(ok: boolean, memberOrError: table|nil|string)
GroupMemberRepository.findById = function(id, callback)
    GroupMember:find(id, callback)
end

--- @param groupId number
-- @param callback function(ok: boolean, membersOrError: table|string) - full roster for one group
GroupMemberRepository.findByGroupId = function(groupId, callback)
    GroupMember:where("group_id", groupId):get(callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, membersOrError: table|string) - every group this account
--        belongs to (an array, since membership is NOT unique per account - a player can be in
--        more than one group at once)
GroupMemberRepository.findByAccountId = function(accountId, callback)
    GroupMember:where("account_id", accountId):get(callback)
end

--- @param attributes table { group_id, account_id, rank_id (nullable) }
-- @param callback function(ok: boolean, memberOrError: table|string)
GroupMemberRepository.create = function(attributes, callback)
    GroupMember:create(attributes, callback)
end

--- @param id number
-- @param attributes table column -> value (e.g. { rank_id = ... } for rank reassignment)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupMemberRepository.update = function(id, attributes, callback)
    GroupMember:query():where("id", id):update(attributes, callback)
end

--- Kick or self-leave.
-- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupMemberRepository.delete = function(id, callback)
    GroupMember:query():where("id", id):delete(callback)
end

--- Adds to the member's accrued on-duty seconds - a single atomic
-- `stat_workduty_seconds = stat_workduty_seconds + ?` UPDATE, called every
-- GroupDutyService.lua duty tick.
-- @param id number
-- @param seconds number positive integer to add
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupMemberRepository.incrementDutySeconds = function(id, seconds, callback)
    Database.execute("UPDATE `group_members` SET `stat_workduty_seconds` = `stat_workduty_seconds` + ? WHERE `id` = ?", { seconds, id }, callback)
end

--- Resets accrued duty seconds to 0 and stamps last_payout_at - ONE
-- combined atomic UPDATE (not two separate calls), so nothing can
-- interleave a concurrent incrementDutySeconds tick between the reset and
-- the timestamp write.
-- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupMemberRepository.payout = function(id, callback)
    Database.execute("UPDATE `group_members` SET `stat_workduty_seconds` = 0, `last_payout_at` = CURRENT_TIMESTAMP WHERE `id` = ?", { id }, callback)
end

-- Deliberately no flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why. gm_groups reaches this through
-- core/server/GroupService.lua's bridge, never directly.
