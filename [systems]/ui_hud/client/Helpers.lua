-- Text-layout helpers shared by HUD components - ported from an older,
-- unrelated project's own helpers.lua essentially as-is (no class()/
-- instanceof() to rewrite here, these were always plain functions).
Helpers = Helpers or {}

--- @param text string
-- @param maxWidth number
-- @param scale number
-- @param font string|element a font name/element dxGetTextWidth accepts
-- @param colorCoded boolean|nil
-- @return string[] `text` broken into lines that each fit within maxWidth
Helpers.wordWrap = function(text, maxWidth, scale, font, colorCoded)
    local words = {}
    for word in text:gmatch("%S+") do
        words[#words + 1] = word
    end

    local lines = {}
    local currentLine = ""

    for _, word in ipairs(words) do
        local testLine = currentLine == "" and word or currentLine .. " " .. word
        local width = dxGetTextWidth(testLine, scale, font, colorCoded)

        if width > maxWidth then
            if currentLine ~= "" then
                lines[#lines + 1] = currentLine
                currentLine = word
            else
                lines[#lines + 1] = word
                currentLine = ""
            end
        else
            currentLine = testLine
        end
    end

    if currentLine ~= "" then
        lines[#lines + 1] = currentLine
    end

    return lines
end

--- Shrinks text scale as length grows, so a long notification message
--- doesn't overflow its fixed-width card as badly as it would at a flat 1.0 scale.
-- @param text string
-- @return number one of 1 / 0.9 / 0.8 / 0.7
Helpers.calculateTextScale = function(text)
    local length = utf8.len(text) or #text

    if length <= 50 then
        return 1
    elseif length <= 100 then
        return 0.9
    elseif length <= 150 then
        return 0.8
    else
        return 0.7
    end
end
