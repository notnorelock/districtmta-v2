Uuid = Uuid or {}

local HEX_CHARS = "0123456789abcdef"

--- @return string a UUIDv4-shaped identifier
Uuid.generate = function()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (template:gsub("[xy]", function(c)
        local v
        if c == "x" then
            v = math.random(0, 15)
        else
            v = math.random(8, 11) -- variant bits (8, 9, a, or b)
        end
        return HEX_CHARS:sub(v + 1, v + 1)
    end))
end
