-- Active Record model for the group_ranks table - one row per rank within
-- a group (Group.lua), each with its own duty skin, hourly duty pay rate,
-- and permission set. permissions is a "text" column holding a
-- toJSON/fromJSON-encoded flat boolean object ({ manage_members=,
-- manage_ranks=, is_leader= }) - GroupRankRepository.lua is the only place
-- that touches the encoding/decoding, same convention Vehicle.lua's own
-- JSON columns use.
GroupRank = Model:extend("group_ranks", {
    { name = "id", type = "id", primaryKey = true },
    { name = "group_id", type = "reference", nullable = false, references = { table = "groups", column = "id" } },
    { name = "name", type = "string", length = 32, nullable = false },
    { name = "skin", type = "integer", nullable = false },
    -- Money per full hour of accrued duty time, paid out via /dutypayout
    -- (see gm_groups/server/GroupCommands.lua). 0 = this rank never gets
    -- a duty payout (typical for gang ranks, which have no fixed wage).
    { name = "hourly_reward", type = "integer", nullable = false, default = 0 },
    { name = "permissions", type = "text", nullable = false },
    -- Lower = more senior. Doubles as the seniority comparator for
    -- manage_members/manage_ranks checks (a rank can only act on a member
    -- currently at, or being assigned to, a STRICTLY HIGHER sort_order -
    -- i.e. less senior than itself) - see GroupEndpoints.lua.
    { name = "sort_order", type = "integer", nullable = false, default = 0 },
    { name = "created_at", type = "timestamp", default = "CURRENT_TIMESTAMP" },
})

GroupRank:belongsTo("group", Group, "group_id")
Group:hasMany("ranks", GroupRank, "group_id")
