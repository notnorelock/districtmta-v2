-- Fluent SQL builder producing MySQL `?`-parameterized statements.
-- Identifiers go through MTA's `??` unquoted placeholder rather than being spliced into the SQL string.

QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

--- @param table string
-- @return QueryBuilder
QueryBuilder.new = function(tableName)
    return setmetatable({
        _table = tableName,
        _wheres = {},
        _orderBy = nil,
        _limit = nil,
        _offset = nil,
    }, QueryBuilder)
end

--- @param column string
-- @param operatorOrValue any if only two args are given, this is the value and operator defaults to "="
-- @param value any|nil
-- @return QueryBuilder self
function QueryBuilder:where(column, operatorOrValue, value)
    local operator = "="
    local actualValue = operatorOrValue

    if value ~= nil then
        operator = operatorOrValue
        actualValue = value
    end

    self._wheres[#self._wheres + 1] = { column = column, operator = operator, value = actualValue }
    return self
end

--- @param column string
-- @param direction "ASC"|"DESC"
-- @return QueryBuilder self
function QueryBuilder:orderBy(column, direction)
    self._orderBy = { column = column, direction = (direction == "DESC") and "DESC" or "ASC" }
    return self
end

--- @param count number
-- @return QueryBuilder self
function QueryBuilder:limit(count)
    self._limit = count
    return self
end

--- @param count number
-- @return QueryBuilder self
function QueryBuilder:offset(count)
    self._offset = count
    return self
end

-- Model.NULL as a condition value produces a literal `?? IS NULL` / `?? IS NOT NULL`
-- with no `?` placeholder, since `= ?`/`!= ?` never matches/excludes NULL
-- in MySQL regardless of the bound value - `= NULL` and `!= NULL` are
-- BOTH always false, never true, for any row (including one whose column
-- actually is NULL), so a plain operator-as-is substitution here would
-- silently return zero rows forever instead of erroring (confirmed live:
-- ItemRepository.findOwnerless's :where("owner_account_id", Model.NULL)
-- - defaulting to "=" - never matched a single dropped item's row).
-- "IS"/"IS NOT" pass through as-is (some existing callers already spell
-- it out explicitly, e.g. AccountPenaltyRepository.lua/
-- AdminDutySessionRepository.lua's :where(column, "IS", Model.NULL));
-- "="/"=="/"!="/"<>" are mapped to their NULL-safe equivalent so a caller
-- using the default 2-arg :where(column, Model.NULL) form (implicit "=")
-- still gets correct SQL. Any other operator against Model.NULL is a
-- caller bug (not a valid SQL NULL comparison) and errors immediately
-- rather than emitting invalid/always-false SQL.
local NULL_OPERATOR_MAP = {
    ["="] = "IS",
    ["=="] = "IS",
    ["!="] = "IS NOT",
    ["<>"] = "IS NOT",
    ["IS"] = "IS",
    ["IS NOT"] = "IS NOT",
}

-- @return string clauseWithLeadingSpaceOrEmpty, table parameters
function QueryBuilder:_buildWhere()
    if #self._wheres == 0 then
        return "", {}
    end

    local parts = {}
    local parameters = {}

    for _, condition in ipairs(self._wheres) do
        if condition.value == Model.NULL then
            local nullOperator = NULL_OPERATOR_MAP[condition.operator]
            assert(nullOperator, "QueryBuilder:where() with Model.NULL only supports =/!=/<>, got: " .. tostring(condition.operator))
            parts[#parts + 1] = "?? " .. nullOperator .. " NULL"
            parameters[#parameters + 1] = condition.column
        else
            parts[#parts + 1] = "?? " .. condition.operator .. " ?"
            parameters[#parameters + 1] = condition.column
            parameters[#parameters + 1] = condition.value
        end
    end

    return " WHERE " .. table.concat(parts, " AND "), parameters
end

--- @param columns table|nil array of column names, defaults to "*"
-- @param callback function(ok: boolean, rowsOrError: table|string)
function QueryBuilder:get(columns, callback)
    if type(columns) == "function" then
        callback = columns
        columns = nil
    end

    local selectList = "*"
    local selectParameters = {}
    if type(columns) == "table" and #columns > 0 then
        local placeholders = {}
        for i, column in ipairs(columns) do
            placeholders[i] = "??"
            selectParameters[i] = column
        end
        selectList = table.concat(placeholders, ", ")
    end

    local whereClause, whereParameters = self:_buildWhere()

    local parameters = {}
    for _, value in ipairs(selectParameters) do
        parameters[#parameters + 1] = value
    end
    parameters[#parameters + 1] = self._table
    for _, value in ipairs(whereParameters) do
        parameters[#parameters + 1] = value
    end

    local sql = "SELECT " .. selectList .. " FROM ??" .. whereClause

    if self._orderBy then
        sql = sql .. " ORDER BY ?? " .. self._orderBy.direction
        parameters[#parameters + 1] = self._orderBy.column
    end

    if self._limit then
        sql = sql .. " LIMIT " .. tostring(math.floor(self._limit))
    end

    if self._offset then
        sql = sql .. " OFFSET " .. tostring(math.floor(self._offset))
    end

    Database.query(sql, parameters, callback)
end

--- @param callback function(ok: boolean, rowOrError: table|nil|string)
function QueryBuilder:first(callback)
    self:limit(1)
    self:get(function(ok, rows)
        if not ok then
            callback(false, rows)
            return
        end
        callback(true, rows[1])
    end)
end

--- @param callback function(ok: boolean, countOrError: number|string)
function QueryBuilder:count(callback)
    local whereClause, whereParameters = self:_buildWhere()
    local sql = "SELECT COUNT(*) AS total FROM ??" .. whereClause

    local parameters = { self._table }
    for _, value in ipairs(whereParameters) do
        parameters[#parameters + 1] = value
    end

    Database.queryOne(sql, parameters, function(ok, row)
        if not ok then
            callback(false, row)
            return
        end
        callback(true, row and tonumber(row.total) or 0)
    end)
end

--- @param callback function(ok: boolean, existsOrError: boolean|string)
function QueryBuilder:exists(callback)
    self:count(function(ok, count)
        if not ok then
            callback(false, count)
            return
        end
        callback(true, count > 0)
    end)
end

--- @param data table column -> value (omit the AUTO_INCREMENT primary key)
-- @param callback function(ok: boolean, dataOrError: table|string, lastInsertId: number|nil)
function QueryBuilder:insert(data, callback)
    local columnPlaceholders = {}
    local valuePlaceholders = {}
    local columnParameters = {}
    local valueParameters = {}

    for column, value in pairs(data) do
        columnPlaceholders[#columnPlaceholders + 1] = "??"
        columnParameters[#columnParameters + 1] = column

        if value == Model.NULL then
            -- MTA's dbQuery/dbExec have no `?` placeholder that binds to SQL NULL, so it's spliced in literally.
            valuePlaceholders[#valuePlaceholders + 1] = "NULL"
        else
            valuePlaceholders[#valuePlaceholders + 1] = "?"
            valueParameters[#valueParameters + 1] = value
        end
    end

    local sql = "INSERT INTO ?? (" .. table.concat(columnPlaceholders, ", ") ..
        ") VALUES (" .. table.concat(valuePlaceholders, ", ") .. ")"

    local parameters = { self._table }
    for _, value in ipairs(columnParameters) do
        parameters[#parameters + 1] = value
    end
    for _, value in ipairs(valueParameters) do
        parameters[#parameters + 1] = value
    end

    Database.insert(sql, parameters, function(ok, affectedRowsOrError, lastInsertId)
        if not ok then
            callback(false, affectedRowsOrError)
            return
        end
        callback(true, data, lastInsertId)
    end)
end

--- @param data table column -> value. A value of Model.NULL writes SQL NULL for that column.
-- @param callback function(ok: boolean, affectedRowsOrError: number|string)
function QueryBuilder:update(data, callback)
    local setParts = {}
    local setParameters = {}

    for column, value in pairs(data) do
        if value == Model.NULL then
            setParts[#setParts + 1] = "?? = NULL"
            setParameters[#setParameters + 1] = column
        else
            setParts[#setParts + 1] = "?? = ?"
            setParameters[#setParameters + 1] = column
            setParameters[#setParameters + 1] = value
        end
    end

    local whereClause, whereParameters = self:_buildWhere()

    local parameters = { self._table }
    for _, value in ipairs(setParameters) do
        parameters[#parameters + 1] = value
    end
    for _, value in ipairs(whereParameters) do
        parameters[#parameters + 1] = value
    end

    local sql = "UPDATE ?? SET " .. table.concat(setParts, ", ") .. whereClause

    Database.execute(sql, parameters, callback)
end

--- @param callback function(ok: boolean, affectedRowsOrError: number|string)
function QueryBuilder:delete(callback)
    local whereClause, whereParameters = self:_buildWhere()
    local sql = "DELETE FROM ??" .. whereClause

    local parameters = { self._table }
    for _, value in ipairs(whereParameters) do
        parameters[#parameters + 1] = value
    end

    Database.execute(sql, parameters, callback)
end
