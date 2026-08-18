--- XORs `text` against `key`, repeating the key as needed.
-- @param text string
-- @param key string non-empty
-- @return string same length as text, XORed byte-by-byte
function xorString(text, key)
    local keyLength = #key
    local out = {}

    for i = 1, #text do
        local textByte = string.byte(text, i)
        local keyByte = string.byte(key, ((i - 1) % keyLength) + 1)
        out[i] = string.char(bitXor(textByte, keyByte))
    end

    return table.concat(out)
end

-- toJSON always wraps its argument in a top-level array (e.g. '[ "x" ]'),
-- so this strips the outer brackets before embedding into JS.
function toJsonValue(value)
    local json = toJSON(value, true)
    return json:sub(2, -2)
end

-- Escapes a Lua string for safe embedding inside a single-quoted JS literal.
function jsStringLiteral(value)
    local escaped = tostring(value)
        :gsub("\\", "\\\\")
        :gsub("'", "\\'")
        :gsub("\n", "\\n")
        :gsub("\r", "")
    return "'" .. escaped .. "'"
end

-- XOR then base64 (base64Encode/Decode are removed in current MTA -
-- encodeString/decodeString("base64", ..., {}) is the replacement).
-- @param plaintext string
-- @param key string
-- @return string base64
function obfuscatePayload(plaintext, key)
    if type(key) ~= "string" or #key == 0 then
        return plaintext
    end
    return encodeString("base64", xorString(plaintext, key), {})
end

-- @param encoded string base64
-- @param key string
-- @return string|nil plaintext, or nil if decoding failed
function deobfuscatePayload(encoded, key)
    if type(key) ~= "string" or #key == 0 then
        return encoded
    end

    local decoded = decodeString("base64", encoded, {})
    if type(decoded) ~= "string" then
        return nil
    end

    return xorString(decoded, key)
end