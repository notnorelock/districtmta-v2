-- Copied from https://github.com/MultiRPG/MTA_2FA-Lib (MIT License,
-- Copyright (c) 2021 Inder00 <admin@multirpg.pl>), with one bug fix (see
-- FIXED comment below) and one addition (Totp.verify, not in the
-- original library - see its own doc comment further down).
--
-- Namespaced under Totp.* rather than left as bare globals
-- (generateSecretKey/generateHotpCode/generateTotpCode) - core_shared's
-- other modules (ErrorCodes, Enums, ValidationRules) all use a table
-- namespace, and bare globals this generic risk colliding with some
-- other resource's own global by coincidence.

Totp = Totp or {}

-- base32 hash table
local base32Alphabet = {
    [0] = 65, [1] = 66, [2] = 67, [3] = 68, [4] = 69, [5] = 70,
    [6] = 71, [7] = 72, [8] = 73, [9] = 74, [10] = 75, [11] = 76,
    [12] = 77, [13] = 78, [14] = 79, [15] = 80, [16] = 81, [17] = 82,
    [18] = 83, [19] = 84, [20] = 85, [21] = 86, [22] = 87, [23] = 88,
    [24] = 89, [25] = 90, [26] = 50, [27] = 51, [28] = 52, [29] = 53,
    [30] = 54, [31] = 55,

    [50] = 26, [51] = 27, [52] = 28, [53] = 29,
    [54] = 30, [55] = 31, [65] = 0,  [66] = 1,  [67] = 2,  [68] = 3,
    [69] = 4,  [70] = 5, [71] = 6,  [72] = 7,  [73] = 8,  [74] = 9,
    [75] = 10, [76] = 11, [77] = 12, [78] = 13, [79] = 14, [80] = 15,
    [81] = 16, [82] = 17, [83] = 18, [84] = 19, [85] = 20, [86] = 21,
    [87] = 22, [88] = 23, [89] = 24, [90] = 25,
}

-- hmac algorithm block size
local algorithmBlockSize = {
    ["md5"] = 64,
    ["sha1"] = 64,
    ["sha224"] = 64,
    ["sha256"] = 64,
    ["sha384"] = 128,
    ["sha512"] = 128,
}

-- hmac encryption
local function hmac( key, message, hashAlgorithm )
    local blockSize = algorithmBlockSize[hashAlgorithm]
    assert( blockSize, "Invalid hash algorithm" )

    if #key > blockSize then
        -- FIXED: original called hash( key ) - a ONE-argument call, so
        -- MTA's hash(algorithm, data) native received `key` as the
        -- `algorithm` parameter and nil as `data`, silently producing
        -- garbage instead of erroring. Correct call passes the algorithm
        -- explicitly and hashes the actual key bytes. Unreachable with
        -- this project's default 16-char base32 secret (~10 decoded
        -- bytes, well under the 64-byte block size), but must be correct
        -- for any future longer-secret configuration.
        key = hash( hashAlgorithm, key )
    end

    local i_key_pad = key:gsub( '.', function( a ) return string.char( bitXor( string.byte( a ), 0x36) ) end) .. string.rep( string.char( 0x36 ), blockSize - #key )
    local o_key_pad = key:gsub( '.', function( a ) return string.char( bitXor( string.byte( a ), 0x5c) ) end) .. string.rep( string.char( 0x5c ), blockSize - #key )

    return hash( hashAlgorithm, o_key_pad .. hash( hashAlgorithm, i_key_pad .. message ):gsub('..', function( hexval ) return string.char( tonumber( hexval, 16 ) ) end) )
end

-- base32 decryption
local function base32Decode( secret )
    local output = {}
    local n = 0
    local bs = 0
    for i, v in ipairs( { secret:byte(1, -1) } ) do
        n = bitLShift( n, 5 )
        n = n + base32Alphabet[ v ]
        bs = ( bs + 5 ) % 8
        if ( bs < 5 ) then
            output[ #output + 1 ] = bitRShift( bitAnd( n, bitLShift( 0xFF, bs ) ), bs )
        end
    end
    return string.char( unpack( output ) )
end

-- generation code
local function getHashCode( secret, counter, algorithm, secretPeriod, digits )
    assert( type( secret ) == "string", "Bad argument 1 @ getHashCode [string expected, got " .. type( secret ) .. "]" )
    assert( type( counter ) == "number", "Bad argument 2 @ getHashCode [number expected, got " .. type( counter ) .. "]" )

    local codeRound = math.floor( counter / ( tonumber(secretPeriod) or 30 ) )
    local codeHash = hmac( base32Decode( secret ), string.char( 0, 0, 0, 0, bitAnd( codeRound, 0xFF000000 ) / 0x1000000, bitAnd( codeRound, 0xFF0000 ) / 0x10000, bitAnd( codeRound, 0xFF00 ) / 0x100, bitAnd( codeRound, 0xFF ) ), (algorithm or "sha1") ):gsub('..', function( hexval ) return string.char( tonumber( hexval, 16 ) ) end)
    local codeOffset = bitAnd( codeHash:sub( -1 ):byte( 1, 1 ), 0xF )
    local codeToken = 0 for i = 1, 4 do codeToken = bitLShift( codeToken, 8 ) + bitAnd( codeHash:byte( codeOffset + i ), 0xFF ) end

    return string.format( "%0" .. (tonumber(digits) or 6) .. "d", bitAnd( codeToken, 0x7FFFFFFF ) % 10 ^ (tonumber(digits) or 6) )
end

-- generate random secret key ( Totp.generateSecretKey( [ number length = 16 ] ) )
Totp.generateSecretKey = function( length )
    local output = ""
    for i = 1, ( tonumber( length ) or 16 ) do
        output = output .. string.char( base32Alphabet[ math.random( 0, 31 ) ] )
    end
    return output
end

-- hotp ( Totp.generateHotpCode( string secret, number counter [, string algorithm = "sha1", number digits = 6 ] ) )
Totp.generateHotpCode = function( secret, counter, algorithm, digits )
    return getHashCode( secret, counter, algorithm, 1, digits )
end

-- totp ( Totp.generateTotpCode( string secret, number timestamp [, string algorithm = "sha1", number secretPeriod = 30, number digits = 6 ] ) )
Totp.generateTotpCode = function( secret, timestamp, algorithm, secretPeriod, digits )
    return getHashCode( secret, timestamp, algorithm, secretPeriod, digits )
end

--- NOT part of the original library - verifies a user-submitted code
--- against a secret, tolerating clock drift between the player's phone
--- and this server. Checks a small window of steps centered on "now"
--- (current step, ±toleranceSteps) rather than an exact match - TOTP's
--- whole failure mode in practice is phone/server clock skew of a few
--- seconds to ~1 minute, and rejecting on that would make the feature
--- unusable for anyone whose phone clock has drifted, which is common
--- and outside the player's control.
-- @param secret string base32 secret, as returned by generateSecretKey
-- @param submittedCode string the 6-digit code the player typed
-- @param toleranceSteps number|nil steps of drift to tolerate each side
--        of "now" - default 1 (±30s at the default 30s step, i.e. any
--        code valid in the last/current/next 30-second window). This is
--        the standard tolerance recommended by RFC 6238 ("network delay,
--        input time") and used by Google Authenticator/most TOTP
--        consumers - wider windows meaningfully increase the odds an
--        attacker's guessed code lands inside SOME valid window.
-- @return boolean
Totp.verify = function( secret, submittedCode, toleranceSteps )
    if type( secret ) ~= "string" or type( submittedCode ) ~= "string" then
        return false
    end

    -- Reject anything that isn't exactly 6 digits before doing any
    -- crypto work - generateTotpCode always zero-pads to 6, so a
    -- same-length string compare below is safe, but only once the shape
    -- of the input is confirmed first.
    if not submittedCode:match( "^%d%d%d%d%d%d$" ) then
        return false
    end

    local steps = tonumber( toleranceSteps ) or 1
    local now = os.time()

    for offset = -steps, steps do
        local candidate = Totp.generateTotpCode( secret, now + ( offset * 30 ), "sha1", 30, 6 )
        if candidate == submittedCode then
            return true
        end
    end

    return false
end
