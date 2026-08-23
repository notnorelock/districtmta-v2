-- Active Record model for the group_invites table - a pending invite to
-- join a group, created by a manage_members member picking an online
-- player in the CEF panel (see gm_groups/server/GroupEndpoints.lua's
-- GROUP_INVITE_PLAYER handler), accepted/declined by the invitee (also
-- server-validated - a player can't accept an invite meant for someone
-- else). Accepting deletes the invite row and creates a group_members
-- row with rank_id = nil (same "no rank yet, leader assigns one" state
-- /creategroup's own leader enrollment does NOT use - only invite-based
-- joins start rankless).
GroupInvite = Model:extend("group_invites", {
    { name = "id", type = "id", primaryKey = true },
    { name = "group_id", type = "reference", nullable = false, references = { table = "groups", column = "id" } },
    -- The invitee - NOT unique per (group_id, account_id) at the schema
    -- level (this ORM has no composite-unique support), so
    -- GroupEndpoints.lua's own GROUP_INVITE_PLAYER handler checks for an
    -- existing pending invite (and existing membership) before creating
    -- a new one, same discipline as every other mutation in that file.
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "invited_by_account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

GroupInvite:belongsTo("group", Group, "group_id")
Group:hasMany("invites", GroupInvite, "group_id")
GroupInvite:belongsTo("account", Account, "account_id")
GroupInvite:belongsTo("inviter", Account, "invited_by_account_id")
Account:hasMany("groupInvites", GroupInvite, "account_id")
