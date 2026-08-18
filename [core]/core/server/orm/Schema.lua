-- Declarative table/column definitions consumed by Model.lua, auto-
-- migrated at startup. See docs/DatabaseContract.md for the full column
-- type DSL and migration behavior.
Schema = Schema or {}

local definitions = {}
local migrated = false

--- @return boolean true once migration has already completed - see
--         docs/DatabaseContract.md's "Migration" section.
Schema.isMigrated = function()
    return migrated
end

--- Registers a table definition. Called once per model, at load time -
--- this only records the definition, it does not touch the database until
--- Schema.migrate() runs (see MySqlAdapterBootstrap.lua).
-- @param tableName string
-- @param columns table ordered array of { name, type, ...options }
Schema.define = function(tableName, columns)
    assert(type(tableName) == "string" and #tableName > 0, "Schema.define requires a table name")
    assert(type(columns) == "table", "Schema.define requires a columns array")

    definitions[tableName] = columns
end

Schema.getDefinition = function(tableName)
    return definitions[tableName]
end

local function columnSql(column)
    local parts = { "`" .. column.name .. "`" }

    if column.type == "id" then
        parts[#parts + 1] = "BIGINT AUTO_INCREMENT"
    elseif column.type == "reference" then
        parts[#parts + 1] = "BIGINT"
    elseif column.type == "uuid" then
        parts[#parts + 1] = "VARCHAR(36)"
    elseif column.type == "string" then
        parts[#parts + 1] = "VARCHAR(" .. tostring(column.length or 255) .. ")"
    elseif column.type == "text" then
        parts[#parts + 1] = "TEXT"
    elseif column.type == "integer" then
        parts[#parts + 1] = "INT"
    elseif column.type == "boolean" then
        parts[#parts + 1] = "TINYINT(1)"
    elseif column.type == "timestamp" then
        parts[#parts + 1] = "TIMESTAMP"
    elseif column.type == "enum" then
        assert(type(column.values) == "table" and #column.values > 0,
            "Schema: 'enum' column '" .. column.name .. "' requires a non-empty values array")

        local literals = {}
        for i, value in ipairs(column.values) do
            assert(type(value) == "string" and value:match("^[%w_]+$"),
                "Schema: 'enum' column '" .. column.name .. "' has an invalid value '" .. tostring(value) .. "'")
            literals[i] = "'" .. value .. "'"
        end
        parts[#parts + 1] = "ENUM(" .. table.concat(literals, ", ") .. ")"
    else
        error("Schema: unknown column type '" .. tostring(column.type) .. "' for column '" .. column.name .. "'")
    end

    if column.nullable == false or column.primaryKey then
        parts[#parts + 1] = "NOT NULL"
    elseif column.type == "timestamp" and column.nullable ~= true then
        -- timestamps default to NULL explicitly, avoiding MySQL's
        -- implicit "first TIMESTAMP column defaults to CURRENT_TIMESTAMP"
        -- behavior, which would silently apply to whichever column
        -- happens to be declared first.
        parts[#parts + 1] = "NULL"
    end

    if column.default ~= nil then
        if column.default == "CURRENT_TIMESTAMP" then
            parts[#parts + 1] = "DEFAULT CURRENT_TIMESTAMP"
        elseif type(column.default) == "boolean" then
            parts[#parts + 1] = "DEFAULT " .. (column.default and "1" or "0")
        elseif type(column.default) == "number" then
            parts[#parts + 1] = "DEFAULT " .. tostring(column.default)
        else
            parts[#parts + 1] = "DEFAULT '" .. tostring(column.default) .. "'"
        end
    end

    return table.concat(parts, " ")
end

local function buildCreateTableSql(tableName, columns)
    local lines = {}
    local primaryKeyColumn = nil

    for _, column in ipairs(columns) do
        lines[#lines + 1] = columnSql(column)
        if column.primaryKey then
            primaryKeyColumn = column.name
        end
    end

    if primaryKeyColumn then
        lines[#lines + 1] = "PRIMARY KEY (`" .. primaryKeyColumn .. "`)"
    end

    for _, column in ipairs(columns) do
        if column.unique then
            lines[#lines + 1] = "UNIQUE KEY `uq_" .. tableName .. "_" .. column.name .. "` (`" .. column.name .. "`)"
        end
        if column.references then
            lines[#lines + 1] = ("FOREIGN KEY (`%s`) REFERENCES `%s` (`%s`)"):format(
                column.name, column.references.table, column.references.column or "id"
            )
        end
    end

    return "CREATE TABLE IF NOT EXISTS `" .. tableName .. "` (\n  " ..
        table.concat(lines, ",\n  ") .. "\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
end

local function existingColumnNames(tableName, callback)
    Database.query("SHOW COLUMNS FROM `" .. tableName .. "`", {}, function(ok, rows)
        if not ok then
            -- Table doesn't exist yet - not an error at this stage, just an empty set.
            callback({})
            return
        end

        local names = {}
        for _, row in ipairs(rows) do
            names[row.Field] = true
        end
        callback(names)
    end)
end

local function migrateTable(tableName, columns, onDone)
    local createSql = buildCreateTableSql(tableName, columns)

    Database.execute(createSql, {}, function(createOk, createError)
        if not createOk then
            Logger.error("Schema", "CREATE TABLE failed", { table = tableName, error = tostring(createError) })
            onDone()
            return
        end

        existingColumnNames(tableName, function(existing)
            local pending = 0
            local function maybeDone()
                pending = pending - 1
                if pending <= 0 then
                    onDone()
                end
            end

            local toAdd = {}
            for _, column in ipairs(columns) do
                if not existing[column.name] then
                    toAdd[#toAdd + 1] = column
                end
            end

            if #toAdd == 0 then
                onDone()
                return
            end

            pending = #toAdd
            for _, column in ipairs(toAdd) do
                local alterSql = "ALTER TABLE `" .. tableName .. "` ADD COLUMN " .. columnSql(column)
                Database.execute(alterSql, {}, function(alterOk, alterError)
                    if not alterOk then
                        Logger.error("Schema", "ADD COLUMN failed", { table = tableName, column = column.name, error = tostring(alterError) })
                    else
                        Logger.info("Schema", "Column added", { table = tableName, column = column.name })
                    end
                    maybeDone()
                end)
            end
        end)
    end)
end

--- Creates missing tables/columns for every registered model. Runs
--- asynchronously and sequentially - does NOT finish by the time this
--- call returns. See docs/DatabaseContract.md's "Migration" section for
--- why callers must wait for Events.DATABASE_READY/Schema.isMigrated()
--- rather than onResourceStart.
-- @param onComplete function()|nil called once every table has been migrated
Schema.migrate = function(onComplete)
    local tableNames = {}
    for tableName in pairs(definitions) do
        tableNames[#tableNames + 1] = tableName
    end
    table.sort(tableNames)

    local function migrateNext(index)
        local tableName = tableNames[index]
        if not tableName then
            migrated = true
            Logger.info("Schema", "Migration complete", { tables = #tableNames })
            if onComplete then
                onComplete()
            end
            return
        end

        migrateTable(tableName, definitions[tableName], function()
            migrateNext(index + 1)
        end)
    end

    migrateNext(1)
end
