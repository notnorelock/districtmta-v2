-- Thin facade over the Group Active Record model - mirrors
-- VehicleRepository.lua's own shape/conventions exactly. Owns the
-- toJSON/fromJSON boundary for duty_position - every row this repository
-- hands back has that field already decoded into a real Lua table (or nil).
GroupRepository = GroupRepository or {}

-- gm_groups (a separate resource) has no access to Model.NULL - see
-- VehicleRepository.lua's own NULL_SENTINEL comment for the full
-- reasoning (triggerEvent copies tables across the resource boundary
-- rather than preserving identity, so Model.NULL's reference-equality
-- sentinel trick can't survive the trip). gm_groups sends this string
-- constant instead to explicitly clear duty_position back to SQL NULL,
-- and this file translates it to the real Model.NULL right before it
-- reaches QueryBuilder.
local NULL_SENTINEL = "__GROUP_REPOSITORY_NULL__"

--- @param group table a Group instance (or plain row) - mutated in place
-- @return table the same table, for chaining
local function decodeJsonColumns(group)
    if not group then
        return group
    end
    if type(group.duty_position) == "string" then
        group.duty_position = fromJSON(group.duty_position) or nil
    end
    return group
end

--- @param attributes table plain column -> value, duty_position as a real
--        Lua table (or NULL_SENTINEL for an explicit SQL NULL)
-- @return table a NEW table (does not mutate `attributes`)
local function encodeJsonColumns(attributes)
    local encoded = {}
    for key, value in pairs(attributes) do
        if value == NULL_SENTINEL then
            encoded[key] = Model.NULL
        else
            encoded[key] = value
        end
    end
    if type(encoded.duty_position) == "table" and encoded.duty_position ~= Model.NULL then
        encoded.duty_position = toJSON(encoded.duty_position)
    end
    return encoded
end

--- @param id number
-- @param callback function(ok: boolean, groupOrError: table|nil|string)
GroupRepository.findById = function(id, callback)
    Group:find(id, function(ok, group)
        callback(ok, ok and decodeJsonColumns(group) or group)
    end)
end

--- @param callback function(ok: boolean, groupsOrError: table|string)
GroupRepository.findAll = function(callback)
    Group:query():get(function(ok, groups)
        if not ok then
            callback(false, groups)
            return
        end
        for _, group in ipairs(groups) do
            decodeJsonColumns(group)
        end
        callback(true, groups)
    end)
end

--- @param accountId number
-- @param callback function(ok: boolean, groupsOrError: table|string)
GroupRepository.findByLeaderAccountId = function(accountId, callback)
    Group:where("leader_account_id", accountId):get(function(ok, groups)
        if not ok then
            callback(false, groups)
            return
        end
        for _, group in ipairs(groups) do
            decodeJsonColumns(group)
        end
        callback(true, groups)
    end)
end

--- @param attributes table column -> value (duty_position as a real Lua table or omitted)
-- @param callback function(ok: boolean, groupOrError: table|string)
GroupRepository.create = function(attributes, callback)
    Group:create(encodeJsonColumns(attributes), function(ok, group)
        callback(ok, ok and decodeJsonColumns(group) or group)
    end)
end

--- @param id number
-- @param attributes table column -> value (duty_position as a real Lua table, or NULL_SENTINEL to clear it)
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupRepository.update = function(id, attributes, callback)
    Group:query():where("id", id):update(encodeJsonColumns(attributes), callback)
end

--- Does NOT cascade - callers must delete this group's ranks and members
--- first (see gm_groups/server/GroupCommands.lua's /deletegroup, which
--- does so in sequence via the bridge before calling this).
-- @param id number
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
GroupRepository.delete = function(id, callback)
    Group:query():where("id", id):delete(callback)
end

-- Deliberately no flat exported wrappers - see VehicleRepository.lua's own
-- module comment on why (a callback can never cross a resource boundary).
-- gm_groups reaches this through core/server/GroupService.lua's
-- GROUP_REPOSITORY_REQUEST/_RESPONSE bridge, never directly.
