-- Resyncs each account's enabled-toggle list into ElementData on login
-- (mirrors gm_licenses/server/LicenseExamService.lua's own
-- resyncElementData pattern) and handles SETTINGS_TOGGLE requests -
-- re-validates the id against SettingsRegistry's whitelist, applies the
-- effect client-side via SETTINGS_APPLY, and writes the FULL updated
-- enabled-id list through to the database immediately (write-through,
-- no flush tick - a settings toggle is a discrete, infrequent user
-- action, not continuously-accruing state).
SettingsService = SettingsService or {}

--- Layers stored overrides on top of SettingsRegistry's own defaults -
--- the direct replacement for the reference pd_* script's own
--- {"default"} sentinel: instead of a magic client-side "load hardcoded
--- defaults" signal, the SERVER always computes the effective set and
--- sends the real, final list every time. Keeps the default
--- source-of-truth in exactly one place (SettingsRegistry.lua).
-- @param storedEnabledIds table|nil the account's own stored "enabled" array
-- @return table array of ids that are effectively enabled right now
local function applyDefaults(storedEnabledIds)
    local stored = {}
    if storedEnabledIds then
        for _, id in ipairs(storedEnabledIds) do
            stored[id] = true
        end
    end

    local effective = {}
    for id, config in pairs(SettingsRegistry) do
        local isEnabled = stored[id]
        if isEnabled == nil then
            isEnabled = config.defaultEnabled == true
        end
        if isEnabled then
            effective[#effective + 1] = id
        end
    end
    return effective
end

--- Replays EVERY registry id's real effect on (re)connect, not just the
--- ones present in the effective set, so a toggle that used to be
--- enabled and is now absent (e.g. registry default changed) still gets
--- its OFF effect applied, not left however the client happened to boot.
-- @param player element
local function resyncElementData(player)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    SettingsBridge.call("findByAccountId", { accountId }, function(ok, rowOrError)
        if not ok then
            Logger.error("SettingsService", "Failed to load player settings", { accountId = accountId, error = tostring(rowOrError) })
            return
        end
        if not isElement(player) then
            return
        end

        local storedEnabledIds = rowOrError and rowOrError.enabled or nil
        local effective = applyDefaults(storedEnabledIds)

        setElementData(player, ElementData.Player.SETTINGS, effective)

        local enabledLookup = {}
        for _, id in ipairs(effective) do
            enabledLookup[id] = true
        end
        for id in pairs(SettingsRegistry) do
            triggerClientEvent(player, Events.SETTINGS_APPLY, resourceRoot, { id = id, enabled = enabledLookup[id] == true })
        end

        triggerClientEvent(player, Events.SETTINGS_SYNCED, resourceRoot, effective)
    end)
end

-- Client -> server: player toggled one setting - re-validates the id,
-- computes the new full enabled-id list, writes it through immediately,
-- applies the effect, and confirms back to the panel.
addEvent(Events.SETTINGS_TOGGLE, true)
addEventHandler(Events.SETTINGS_TOGGLE, root, function(id, enabled)
    local player = client
    if not settingsRegistryIsValidId(id) or type(enabled) ~= "boolean" then
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    SettingsBridge.call("findByAccountId", { accountId }, function(ok, rowOrError)
        if not ok then
            Logger.error("SettingsService", "Failed to load player settings for toggle", { accountId = accountId, error = tostring(rowOrError) })
            return
        end

        local storedEnabledIds = rowOrError and rowOrError.enabled or nil
        local stored = {}
        if storedEnabledIds then
            for _, existingId in ipairs(storedEnabledIds) do
                stored[existingId] = true
            end
        end
        -- Lua idiom: `enabled or nil` maps false -> nil (removes the
        -- key) and true -> true (sets it) in one line.
        stored[id] = enabled or nil

        local newEnabledIds = {}
        for existingId in pairs(stored) do
            newEnabledIds[#newEnabledIds + 1] = existingId
        end

        SettingsBridge.call("upsert", { accountId, newEnabledIds }, function(upsertOk, upsertResultOrError)
            if not upsertOk then
                Logger.error("SettingsService", "Failed to persist player setting toggle", { accountId = accountId, id = id, error = tostring(upsertResultOrError) })
                return
            end
            if not isElement(player) then
                return
            end

            triggerClientEvent(player, Events.SETTINGS_APPLY, resourceRoot, { id = id, enabled = enabled })

            local effective = applyDefaults(newEnabledIds)
            triggerClientEvent(player, Events.SETTINGS_SYNCED, resourceRoot, effective)
        end)
    end)
end)

-- Every consuming resource needs its own addEvent for this event even
-- though core already declares it - see LicenseExamService.lua's own
-- identical comment on why.
addEvent(Events.PLAYER_ACCOUNT_RESOLVED, true)
addEventHandler(Events.PLAYER_ACCOUNT_RESOLVED, root, function(account)
    if type(account) ~= "table" or type(account.id) ~= "number" then
        return
    end
    resyncElementData(source)
end)
