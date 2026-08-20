local FONTS_UNPROCESSED = {
    Bold = {
        big = 32,
        small = 14,
        normal = 18.5,
    },
    Black = {
        big = 32,
        small = 14,
        normal = 18.5,
    },
    Regular = {
        big = 32,
        small = 14,
        normal = 18.5,
    },
    SemiBold = {
        big = 32,
        small = 14,
        normal = 18.5,
    }
}

local FONTS = {}

addEventHandler('onClientResourceStart', resourceRoot, function()
    for fontName, fontData in pairs(FONTS_UNPROCESSED) do
        local fontPath = string.format('client/html/assets/TitilliumWeb-%s.ttf', fontName)

        if fileExists(fontPath) then
            for sizeName, size in pairs(fontData) do
                local font = dxCreateFont(fontPath, size)
                if font then
                    -- lowercase the font name and size name to match the naming convention used in the rest of the code
                    FONTS[string.lower(string.format('%s_%s', fontName, sizeName))] = font
                end
            end
        end
    end
end)

addEventHandler('onClientResourceStop', resourceRoot, function()
    for k, v in pairs(FONTS) do
        if isElement(v) then
            destroyElement(v)
            FONTS[k] = nil
        end
    end
end)

function getUIFont(fontName)
    return FONTS[fontName] or false
end