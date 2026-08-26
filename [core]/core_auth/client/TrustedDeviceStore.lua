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

TrustedDeviceStore = TrustedDeviceStore or {}

-- Distinct key from CredentialStore's own - no reason for these two
-- unrelated local files to be XORed with the same key.
local LOCAL_OBFUSCATION_KEY = "dIsTr1ct-l0c4l-dvc-v1"
local TRUSTED_DEVICE_FILE = "@trusted_device.xml"

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

--- Saves the trusted-device token, obfuscated, to TRUSTED_DEVICE_FILE
--- (overwrites any existing file).
-- @param token string
TrustedDeviceStore.save = function(token)
    local xml = xmlCreateFile(TRUSTED_DEVICE_FILE, "trustedDevice")
    if not xml then
        Logger.warn("TrustedDeviceStore", "Failed to create trusted_device.xml")
        return
    end

    xmlNodeSetAttribute(xml, "token", obfuscateLocal(token))
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

--- @return string|nil the saved token, or nil if none exists
TrustedDeviceStore.load = function()
    local xml = xmlLoadFile(TRUSTED_DEVICE_FILE)
    if not xml then
        return nil
    end

    local token = deobfuscateLocal(xmlNodeGetAttribute(xml, "token"))
    xmlUnloadFile(xml)

    return token
end

--- Deletes any saved trusted-device token.
TrustedDeviceStore.clear = function()
    if fileExists(TRUSTED_DEVICE_FILE) then
        fileDelete(TRUSTED_DEVICE_FILE)
    end
end
