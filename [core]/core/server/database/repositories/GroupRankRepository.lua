-- Thin facade over the GroupRank Active Record model - mirrors
-- VehicleRepository.lua's own shape/conventions. Owns the toJSON/fromJSON
-- boundary for permissions - every row this repository hands back has
-- that field already decoded into a real Lua table.
GroupRankRepository = GroupRankRepository or {}

--- @param rank table a GroupRank instance (or plain row) - mutated in place
-- @return table the same table, for chaining
local function decodeJsonColumns(rank)
    if not rank then
        return rank
    end
    if type(rank.permissions) == "string" then
        rank.permissions = fromJSON(rank.permissions) or {}
    end
    return rank
end

--- @param attributes table plain column -> value, permissions as a real Lua table
-- @return table a NEW table (does not mutate `attributes`)
local function encodeJsonColumns(attributes)
    local encoded = {}
    for key, value in pairs(attributes) do
        encoded[key] = value
    end
    if type(encoded.permissions) == "table" then
        encoded.permissions = toJSON(encoded.permissions)
    end
    return encoded
end

--- @param id number
-- @param callback function(ok: boolean, rankOrError: table|nil|string)
GroupRankRepository.findById = function(id, callback)
    GroupRank:find(id, function(ok, rank)
        callback(ok, ok and decodeJsonColumns(rank) or rank)
    end)
end

--- @param groupId number
-- @param callback function(ok: boolean, ranksOrError: table|string) ordered most-senior-first (sort_order ASC)
GroupRankRepository.findByGroupId = function(groupId, callback)
    GroupRank:where("group_id", groupId):orderBy("sort_order", "ASC"):get(function(ok, ranks)
        if not ok then
            callback(false, ranks)
            return
        end
        for _, rank in ipairs(ranks) do
            decodeJsonColumns(rank)
        end
        callback(true, ranks)
    end)
end

--- @param attributes table column -> value (permissions as a real Lua table)
-- @param callback function(ok: boolean, rankOrError: table|string)
GroupRankRepository.create = function(attributes, callback)
    GroupRank:create(encodeJsonColumns(attributes), function(ok, rank)
        callback(ok, ok and decodeJsonColumns(rank) or rank)
    end)
end

--- @param id number
-- @param attributes table column -> value (permissions as a real Lua table)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupRankRepository.update = function(id, attributes, callback)
    GroupRank:query():where("id", id):update(encodeJsonColumns(attributes), callback)
end

--- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupRankRepository.delete = function(id, callback)
    GroupRank:query():where("id", id):delete(callback)
end

-- Deliberately no flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why. gm_groups reaches this through
-- core/server/GroupService.lua's bridge, never directly.
