-- Local persistence for the trusted-device 2FA-bypass token (see
-- AccountService.lua's own "trusted device" comments for the full
-- server-side design). CRITICAL DIFFERENCE from CredentialStore.lua: the
-- value stored here is NOT a password-equivalent secret in the same sense
-- - it's checked against a SERVER-SIDE HASH (see AccountTrustedDevice.lua's
-- verifier_hash column), so even a fully-reversible local storage format
-- here poses the same risk shape as CredentialStore.lua's OWN existing
-- threat model ("protects against casual local file inspection, not a
-- fully-compromised machine" - see that file's own top comment). The XOR
-- obfuscation below exists for parity/consistency with CredentialStore.lua's
-- bar, not because this value needs stronger LOCAL protection than that
-- file already accepts as sufficient.
--
-- PER-ACCOUNT since the login screen went multi-account (see
-- CredentialStore.lua/AccountSwitcher.tsx): a device trusted for one
-- account's 2FA must never silently bypass 2FA for a DIFFERENT account
-- logged into the same switcher - that would be a real security
-- regression the old single-token-per-device format would have
-- introduced the moment more than one account could sit in the switcher
-- at once. Same list-of-entries shape as CredentialStore.lua, keyed by
-- login instead of holding a single value.

TrustedDeviceStore = TrustedDeviceStore or {}

-- Distinct key from CredentialStore's own - no reason for these two
-- unrelated local files to be XORed with the same key.
local LOCAL_OBFUSCATION_KEY = "dIsTr1ct-l0c4l-dvc-v1"
local TRUSTED_DEVICE_FILE = "@trusted_device.xml"
local MAX_DEVICES = 5

--- XORs `text` against `key`, repeating the key as needed. Identical
--- implementation to CredentialStore.lua's own (kept as a separate copy,
--- not a shared utility - this project has no shared
--- "LocalObfuscation.lua" module, and introducing one now to de-duplicate
--- ~10 lines is out of scope for this feature).
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

--- @return table array of { login, token, lastUsedAt } - malformed child
--         nodes are skipped, not fatal. The OLD single-token format
--         (`<trustedDevice token="..">`) has no login to key it by, so it
--         is simply not readable by this loader - that entry is lost, not
--         migrated (safe: the player just sees a 2FA prompt once more).
local function readDevices()
    local xml = xmlLoadFile(TRUSTED_DEVICE_FILE)
    if not xml then
        return {}
    end

    if xmlNodeGetName(xml) ~= "devices" then
        xmlUnloadFile(xml)
        return {}
    end

    local devices = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local login = deobfuscateLocal(xmlNodeGetAttribute(node, "login"))
        local token = deobfuscateLocal(xmlNodeGetAttribute(node, "token"))
        local lastUsedAt = tonumber(deobfuscateLocal(xmlNodeGetAttribute(node, "lastUsedAt")))

        if login and token and lastUsedAt then
            devices[#devices + 1] = { login = login, token = token, lastUsedAt = lastUsedAt }
        end
    end
    xmlUnloadFile(xml)

    return devices
end

local function writeDevices(devices)
    local xml = xmlCreateFile(TRUSTED_DEVICE_FILE, "devices")
    if not xml then
        Logger.warn("TrustedDeviceStore", "Failed to create trusted_device.xml")
        return
    end

    for _, device in ipairs(devices) do
        local node = xmlCreateChild(xml, "device")
        xmlNodeSetAttribute(node, "login", obfuscateLocal(device.login))
        xmlNodeSetAttribute(node, "token", obfuscateLocal(device.token))
        xmlNodeSetAttribute(node, "lastUsedAt", obfuscateLocal(tostring(device.lastUsedAt)))
    end

    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

--- @param login string
-- @param haystack table array of devices
-- @return number|nil index of the entry matching `login` case-insensitively, nil if not found
local function findIndexByLogin(haystack, login)
    local needle = login:lower()
    for index, device in ipairs(haystack) do
        if device.login:lower() == needle then
            return index
        end
    end
    return nil
end

--- Saves `login`'s trusted-device token, obfuscated - inserts or
--- updates that login's entry, bumps lastUsedAt, evicts the single
--- oldest entry (by lastUsedAt) if this pushes the list past
--- MAX_DEVICES.
-- @param login string
-- @param token string
TrustedDeviceStore.save = function(login, token)
    local devices = readDevices()
    local now = os.time()

    local existingIndex = findIndexByLogin(devices, login)
    if existingIndex then
        devices[existingIndex].token = token
        devices[existingIndex].lastUsedAt = now
    else
        devices[#devices + 1] = { login = login, token = token, lastUsedAt = now }
    end

    if #devices > MAX_DEVICES then
        local oldestIndex = 1
        for index = 2, #devices do
            if devices[index].lastUsedAt < devices[oldestIndex].lastUsedAt then
                oldestIndex = index
            end
        end
        table.remove(devices, oldestIndex)
    end

    writeDevices(devices)
end

--- @param login string
-- @return string|nil the saved token for `login`, or nil if none exists
TrustedDeviceStore.load = function(login)
    local devices = readDevices()
    local index = findIndexByLogin(devices, login)
    return index and devices[index].token or nil
end

--- Deletes `login`'s saved trusted-device token, if any.
-- @param login string
TrustedDeviceStore.clear = function(login)
    local devices = readDevices()
    local index = findIndexByLogin(devices, login)
    if not index then
        return
    end

    table.remove(devices, index)
    writeDevices(devices)
end
