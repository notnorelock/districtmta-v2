-- Thin facade over the GroupInvite Active Record model - mirrors
-- GroupMemberRepository.lua's own shape/conventions. No JSON columns.
GroupInviteRepository = GroupInviteRepository or {}

--- @param id number
-- @param callback function(ok: boolean, inviteOrError: table|nil|string)
GroupInviteRepository.findById = function(id, callback)
    GroupInvite:find(id, callback)
end

--- @param accountId number
-- @param callback function(ok: boolean, invitesOrError: table|string) - every pending invite for this account
GroupInviteRepository.findByAccountId = function(accountId, callback)
    GroupInvite:where("account_id", accountId):get(callback)
end

--- @param groupId number
-- @param callback function(ok: boolean, invitesOrError: table|string) - every pending invite for this group
GroupInviteRepository.findByGroupId = function(groupId, callback)
    GroupInvite:where("group_id", groupId):get(callback)
end

--- @param attributes table { group_id, account_id, invited_by_account_id }
-- @param callback function(ok: boolean, inviteOrError: table|string)
GroupInviteRepository.create = function(attributes, callback)
    GroupInvite:create(attributes, callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupInviteRepository.delete = function(id, callback)
    GroupInvite:query():where("id", id):delete(callback)
end

-- Deliberately no flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why. gm_groups reaches this through
-- core/server/GroupService.lua's bridge, never directly.
