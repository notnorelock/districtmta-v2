-- LOCAL_OBFUSCATION_KEY is a fixed key baked into this client script (it
-- has to be, to survive a client restart with no server round trip) -
-- this raises the bar above a plaintext file, it is NOT a real secret.

CredentialStore = CredentialStore or {}

local LOCAL_OBFUSCATION_KEY = "dIsTr1ct-l0c4l-cr3d-v1"
local CREDENTIALS_FILE = "@credentials.xml"

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

--- Saves login + password, obfuscated, to CREDENTIALS_FILE (overwrites any existing file).
-- @param login string
-- @param password string
CredentialStore.save = function(login, password)
    local xml = xmlCreateFile(CREDENTIALS_FILE, "credentials")
    if not xml then
        Logger.warn("CredentialStore", "Failed to create credentials.xml")
        return
    end

    xmlNodeSetAttribute(xml, "login", obfuscateLocal(login))
    xmlNodeSetAttribute(xml, "password", obfuscateLocal(password))
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

--- @return string|nil login, string|nil password - both nil if no saved credentials exist yet
CredentialStore.load = function()
    local xml = xmlLoadFile(CREDENTIALS_FILE)
    if not xml then
        return nil, nil
    end

    local login = deobfuscateLocal(xmlNodeGetAttribute(xml, "login"))
    local password = deobfuscateLocal(xmlNodeGetAttribute(xml, "password"))
    xmlUnloadFile(xml)

    return login, password
end

--- Deletes any saved credentials.
CredentialStore.clear = function()
    if fileExists(CREDENTIALS_FILE) then
        fileDelete(CREDENTIALS_FILE)
    end
end
