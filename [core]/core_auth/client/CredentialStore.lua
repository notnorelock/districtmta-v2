-- LOCAL_OBFUSCATION_KEY is a fixed key baked into this client script (it
-- has to be, to survive a client restart with no server round trip) -
-- this raises the bar above a plaintext file, it is NOT a real secret.

CredentialStore = CredentialStore or {}

local LOCAL_OBFUSCATION_KEY = "dIsTr1ct-l0c4l-cr3d-v1"
local CREDENTIALS_FILE = "@credentials.xml"
local MAX_ACCOUNTS = 5

-- Root tag name for the CURRENT (list-based) format - the OLD single-slot
-- format used "credentials" as its root tag name (see the migration in
-- list() below, which detects that old tag name specifically to convert
-- an existing player's file rather than silently discarding it).
local ROOT_TAG = "accounts"
local OLD_ROOT_TAG = "credentials"

--- XORs `text` against `key`, repeating the key as needed.
local function xorString(text, key)
    local keyLength = #key
    local out = {}

    for i = 1, #text do
        local textByte = string.byte(text, i)
        local keyByte = string.byte(key, ((i - 1) % keyLength) + 1)
        out[i] = string.char(bitXor(textByte, keyByte))
    end

    return table.concat(out)
end

local function obfuscateLocal(plaintext)
    if type(plaintext) ~= "string" or #plaintext == 0 then
        return ""
    end
    return encodeString("base64", xorString(plaintext, LOCAL_OBFUSCATION_KEY), {})
end

--- @param encoded string|boolean xmlNodeGetAttribute returns `false` (not nil) when the attribute doesn't exist
local function deobfuscateLocal(encoded)
    if type(encoded) ~= "string" or #encoded == 0 then
        return nil
    end

    local decoded = decodeString("base64", encoded, {})
    if type(decoded) ~= "string" then
        return nil
    end

    return xorString(decoded, LOCAL_OBFUSCATION_KEY)
end

--- Writes `accounts` (array of {login, password, savedAt, lastUsedAt})
--- to CREDENTIALS_FILE as one <account> child node per entry - full
--- overwrite, same as the old single-slot save always did (the file is
--- small, no incremental-write complexity needed for up to 5 entries).
local function writeAccounts(accounts)
    local xml = xmlCreateFile(CREDENTIALS_FILE, ROOT_TAG)
    if not xml then
        Logger.warn("CredentialStore", "Failed to create credentials.xml")
        return
    end

    for _, account in ipairs(accounts) do
        local node = xmlCreateChild(xml, "account")
        xmlNodeSetAttribute(node, "login", obfuscateLocal(account.login))
        if account.password then
            xmlNodeSetAttribute(node, "password", obfuscateLocal(account.password))
        end
        xmlNodeSetAttribute(node, "savedAt", obfuscateLocal(tostring(account.savedAt)))
        xmlNodeSetAttribute(node, "lastUsedAt", obfuscateLocal(tostring(account.lastUsedAt)))
    end

    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

--- One-time conversion of an OLD single-slot <credentials login=".."
--- password=".."> file into the new list format - reads the old
--- attributes with the same deobfuscation helpers, builds a one-entry
--- list, writes it back via writeAccounts (so every load after this one
--- reads the new format directly), and returns that list. The old
--- format only ever existed for "remember me" = true logins, so the
--- migrated entry always has a password.
-- @param xml xmlnode the loaded OLD-format root node
local function migrateOldFormat(xml)
    local login = deobfuscateLocal(xmlNodeGetAttribute(xml, "login"))
    local password = deobfuscateLocal(xmlNodeGetAttribute(xml, "password"))
    xmlUnloadFile(xml)

    if not login or not password then
        return {}
    end

    local now = os.time()
    local accounts = { { login = login, password = password, savedAt = now, lastUsedAt = now } }
    writeAccounts(accounts)
    return accounts
end

--- @return table array of { login, password (or nil), savedAt, lastUsedAt }, sorted lastUsedAt desc.
--         Malformed child nodes (missing login/savedAt/lastUsedAt after
--         deobfuscation) are skipped, not fatal to the whole load.
CredentialStore.list = function()
    local xml = xmlLoadFile(CREDENTIALS_FILE)
    if not xml then
        return {}
    end

    if xmlNodeGetName(xml) == OLD_ROOT_TAG then
        return migrateOldFormat(xml)
    end

    local accounts = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local login = deobfuscateLocal(xmlNodeGetAttribute(node, "login"))
        local savedAt = tonumber(deobfuscateLocal(xmlNodeGetAttribute(node, "savedAt")))
        local lastUsedAt = tonumber(deobfuscateLocal(xmlNodeGetAttribute(node, "lastUsedAt")))

        if login and savedAt and lastUsedAt then
            accounts[#accounts + 1] = {
                login = login,
                password = deobfuscateLocal(xmlNodeGetAttribute(node, "password")),
                savedAt = savedAt,
                lastUsedAt = lastUsedAt,
            }
        end
    end
    xmlUnloadFile(xml)

    table.sort(accounts, function(a, b) return a.lastUsedAt > b.lastUsedAt end)
    return accounts
end

--- @param login string
-- @param haystack table array of accounts
-- @return number|nil index of the entry matching `login` case-insensitively, nil if not found
local function findIndexByLogin(haystack, login)
    local needle = login:lower()
    for index, account in ipairs(haystack) do
        if account.login:lower() == needle then
            return index
        end
    end
    return nil
end

--- Inserts or updates `login`'s entry: sets/clears its password per
--- rememberPassword, bumps lastUsedAt to now, keeps savedAt if the entry
--- already existed. Evicts the single oldest (by lastUsedAt) entry if
--- this insert pushes the list past MAX_ACCOUNTS - upsert only ever adds
--- at most one new entry, so at most one eviction is ever needed.
-- @param login string
-- @param password string
-- @param rememberPassword boolean
CredentialStore.upsert = function(login, password, rememberPassword)
    local accounts = CredentialStore.list()
    local now = os.time()
    local storedPassword = rememberPassword and password or nil

    local existingIndex = findIndexByLogin(accounts, login)
    if existingIndex then
        accounts[existingIndex].password = storedPassword
        accounts[existingIndex].lastUsedAt = now
    else
        accounts[#accounts + 1] = { login = login, password = storedPassword, savedAt = now, lastUsedAt = now }
    end

    if #accounts > MAX_ACCOUNTS then
        local oldestIndex = 1
        for index = 2, #accounts do
            if accounts[index].lastUsedAt < accounts[oldestIndex].lastUsedAt then
                oldestIndex = index
            end
        end
        table.remove(accounts, oldestIndex)
    end

    writeAccounts(accounts)
end

--- Updates only lastUsedAt = now for an existing entry (case-insensitive
--- match), no-op if not found - used when logging in via a "recently
--- used" entry without checking "remember me" again, so it stays in the
--- recently-used bucket but its LRU rank freshens.
-- @param login string
CredentialStore.touch = function(login)
    local accounts = CredentialStore.list()
    local index = findIndexByLogin(accounts, login)
    if not index then
        return
    end

    accounts[index].lastUsedAt = os.time()
    writeAccounts(accounts)
end

--- Deletes one entry by case-insensitive login match.
-- @param login string
CredentialStore.remove = function(login)
    local accounts = CredentialStore.list()
    local index = findIndexByLogin(accounts, login)
    if not index then
        return
    end

    table.remove(accounts, index)
    writeAccounts(accounts)
end

--- Deletes the whole file. Kept as a debug/reset primitive - the
--- switcher UI itself never calls "clear all".
CredentialStore.clear = function()
    if fileExists(CREDENTIALS_FILE) then
        fileDelete(CREDENTIALS_FILE)
    end
end
