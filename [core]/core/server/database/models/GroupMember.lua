-- Active Record model for the group_members table - one row per (account,
-- group) membership. account_id is deliberately NOT unique - a player can
-- belong to multiple groups at once, unlike the single-membership model
-- an earlier, unrelated reference implementation this was adapted from
-- used. rank_id is nullable: a freshly-added member with no rank assigned
-- yet can't enter duty (see gm_groups/server/GroupDutyService.lua's own
-- enterDuty guard) until a leader/manage_members-permitted member assigns one.
GroupMember = Model:extend("group_members", {
    { name = "id", type = "id", primaryKey = true },
    { name = "group_id", type = "reference", nullable = false, references = { table = "groups", column = "id" } },
    { name = "account_id", type = "reference", nullable = false, references = { table = "accounts", column = "id" } },
    { name = "rank_id", type = "reference", nullable = true, references = { table = "group_ranks", column = "id" } },
    -- Cumulative on-duty seconds since the last payout - incremented by
    -- GroupDutyService.lua's periodic tick, reset to 0 atomically by
    -- GroupMemberRepository.payout alongside last_payout_at.
    { name = "stat_workduty_seconds", type = "integer", nullable = false, default = 0 },
    { name = "last_payout_at", type = "timestamp", nullable = true },
    { name = "joined_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

GroupMember:belongsTo("group", Group, "group_id")
GroupMember:belongsTo("account", Account, "account_id")
GroupMember:belongsTo("rank", GroupRank, "rank_id")
Group:hasMany("members", GroupMember, "group_id")
Account:hasMany("groupMemberships", GroupMember, "account_id")
