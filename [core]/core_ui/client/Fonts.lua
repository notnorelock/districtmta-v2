-- @author: norelock <github.com/notnorelock>
-- @project: districtmta.pl

-- O KURWA ODKRYŁEŚ JAK CZCIONKI SĄ WCZYTYWANE DO INNYCH CZĘŚCI SKRYPTÓW, JA PIERDOLE NIE DOWIERZAM!!!!!!1!
-- ile ci zapłacili za te odkrycie???/??/?

-- anyway, to nie tak że skrypt udostępniam celowo ponieważ jest w chuj dużo lepszych alternatyw na wczytywanie czcionek
-- po prostu jak widzę że ludzie próbują coś uzyskać co po prostu w czasach innych polskich "serwerów" nazywa się autorskim i musi to być
-- koniecznie zakodowane albo schowane w RAMie to mi się żygać chcę, ja wiem że marnujecie czas jednak platforma już wystarczająco
-- pokazała że już nie warto chować niektórych plików lub nawet je kodować.

-- tak czy siak, miłego czytania bardzo łatwego kodu na rok 2026/2027, kiedy serwer wyszedł :P

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

addEventHandler("onClientResourceStart", resourceRoot, function()
    for fontName, fontData in pairs(FONTS_UNPROCESSED) do
        local fontPath = string.format("client/html/assets/TitilliumWeb-%s.ttf", fontName)

        if fileExists(fontPath) then
            for sizeName, size in pairs(fontData) do
                local font = dxCreateFont(fontPath, size)
                if font then
                    FONTS[string.lower(string.format("%s_%s", fontName, sizeName))] = font
                end
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
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