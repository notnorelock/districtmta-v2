local ICONS             = { 'door', 'marker' }
local GROUND_COUNT      = 4
local GROUND_MULTIPILER = 2
local MARKERS_SUPPORTED = { ['ring'] = true, ['corona'] = true, ['cylinder'] = true }

local Markers           = {}

Markers.font            = false
Markers.text            = {}
Markers.grounds         = {}
Markers.textures        = {}
Markers.iconTargets     = {}  -- Cache for icon + background render targets
Markers.drawDistance    = 60
Markers.fadeDistance    = 0.5

Markers.destroy         = function()
    for k, v in pairs(Markers.textures) do
        if isElement(v) then
            destroyElement(v)
        end

        Markers.textures[k] = nil
    end
    Markers.textures = {}

    -- Clean up icon render targets
    for k, v in pairs(Markers.iconTargets) do
        if isElement(v) then
            destroyElement(v)
        end
        Markers.iconTargets[k] = nil
    end
    Markers.iconTargets = {}

    collectgarbage()
end

Markers.init            = function()
    for k, v in ipairs(ICONS) do
        if not Markers.textures[v] and fileExists(string.format('assets/icons/%s.png', v)) then
            Markers.textures[v] = dxCreateTexture(string.format('assets/icons/%s.png', v), 'argb', false, 'clamp')
        end
    end

    Markers.textures['ground'] = dxCreateTexture('assets/ground.png', 'dxt5', false, 'clamp')
    Markers.textures['background'] = dxCreateTexture('assets/background.png', 'dxt5', false, 'clamp')

    addEventHandler('onClientPreRender', root, Markers.renderMarkers)
    addEventHandler('onClientResourceStop', resourceRoot, Markers.destroy)
    addEventHandler('onClientElementDataChange', root, function(key, oldValue, newValue)
        if getElementType(source) == 'marker' and key == 'text' then
            Markers.removeTarget(source)
            Markers.createTextTarget(source, newValue)
        end
    end)

    if not Markers.font then
        Markers.font = exports.core_ui:getUIFont('bold_big')
    end
end
addEventHandler('onClientResourceStart', resourceRoot, Markers.init)

Markers.createTextTarget = function(marker, text)
    if not isElement(marker) or not text then return end

    if not Markers.text[marker] then
        local w = dxGetTextWidth(text, 1, Markers.font) * 1.1
        local h = dxGetFontHeight(1, Markers.font) * 1.2

        Markers.text[marker] = dxCreateRenderTarget(w, h, true)

        dxSetRenderTarget(Markers.text[marker], true)
        dxSetBlendMode('modulate_add')
        drawBorderedText(text, 0, 4, w, h, 255, 255, 255, 255, 1, Markers.font, 'center', 'top', false, false, false, true)
        dxSetBlendMode('blend')
        dxSetRenderTarget()
    end
end

Markers.getIconTarget = function(icon, r, g, b)
    -- Create cache key based on icon + background color
    local key = string.format('%s_%d_%d_%d', icon, r, g, b)

    if not Markers.iconTargets[key] then
        -- Create render target (256x256 is enough for icon + background)
        local size = 264
        local rt = dxCreateRenderTarget(size, size, true)

        if rt then
            dxSetRenderTarget(rt, true)

            -- Draw background with marker color (centered, 0.6 size relative to 256px = ~154px)
            local bgSize = size
            local bgX = (size - bgSize) / 2
            dxDrawImage(bgX, bgX, bgSize, bgSize, Markers.textures['background'], 0, 0, 0, tocolor(r, g, b, 255))

            -- Draw icon in WHITE (centered, 0.31 size relative to 256px = ~79px, slightly above background)
            local iconSize = size * 0.6
            local iconX = (size - iconSize) / 2
            -- Icon positioned slightly higher to match original offset (1.8 vs 1.75)
            local iconY = iconX - (size * 0.09)  -- Small vertical offset
            dxDrawImage(iconX, iconY, iconSize, iconSize, Markers.textures[icon], 0, 0, 0, tocolor(255, 255, 255, 255))

            dxSetRenderTarget()

            Markers.iconTargets[key] = rt
        end
    end

    return Markers.iconTargets[key]
end

-- Only clears the cached TEXT render target - NOT the ground-ring
-- animation state (see Markers.grounds's own separate lifecycle below).
-- Called both when a marker's text element-data changes (needs a fresh
-- target for the new string) and when it has no text at all (nothing to
-- draw) - neither case should also reset the ground animation, which has
-- nothing to do with text.
Markers.removeTarget = function(el)
    if Markers.text[el] then
        destroyElement(Markers.text[el])
        Markers.text[el] = nil
    end
end

-- typy markerów wspieranych: ring, cylinder, corona
Markers.renderMarkers = function()
    local playerPos = Vector3(getElementPosition(localPlayer))
    local playerInt = getElementInterior(localPlayer)
    local playerDim = getElementDimension(localPlayer)
    local camRx, camRy, camRz = getElementRotation(getCamera())
    local tick = getTickCount()  -- Cache tick for animations

    for _, marker in ipairs(getElementsByType('marker', root, true)) do
        if MARKERS_SUPPORTED[getMarkerType(marker)] then
            local markerInt = getElementInterior(marker)
            local markerDim = getElementDimension(marker)
            local x, y, z = getElementPosition(marker)

            local visible = markerInt == playerInt
                and markerDim == playerDim

            local r, g, b, a = getMarkerColor(marker)
            if a ~= 0 then
                setMarkerColor(marker, r, g, b, 0)
            end

            local alpha = 0
            if visible then
                local drawDistance = getElementData(marker, 'draw_distance') or Markers.drawDistance
                local fadeDistance = drawDistance * Markers.fadeDistance

                local dist = getDistanceBetweenPoints3D(x, y, z, playerPos)
                local progress = (dist - fadeDistance) / (drawDistance - fadeDistance)
                alpha = math.max(0, math.min(255 - (255 * progress), 255))
            end

            if alpha <= 0 then
                -- Marker genuinely out of view (too far/off-screen/wrong
                -- interior-dimension) - full reset, unlike the "no text"
                -- case below which only ever clears the text target.
                Markers.removeTarget(marker)
                Markers.grounds[marker] = nil
            else
                local anim = interpolateBetween(0, 0, 0, 0.10, 0, 0, (tick / 2500), 'SineCurve')
                local size = getMarkerSize(marker) * 2
                local icon = getElementData(marker, 'icon') or 'marker'

                -- Get cached render target for icon + background (background colored, icon white)
                local iconTarget = Markers.getIconTarget(icon, r, g, b)
                if iconTarget then
                    -- Draw single render target with only alpha modulation
                    drawTransformedMaterial(iconTarget, x, y, z + 1.75 + anim, -90, camRy, camRz, 0.6, 0.6, { 255, 255, 255, alpha }, 0, 0, 0)
                end

                Markers.handleGroundAnimation(marker, x, y, z, size, r, g, b, alpha, tick)

                local text = getElementData(marker, 'text')
                if not text then
                    Markers.removeTarget(marker)
                else
                    if not Markers.text[marker] then
                        Markers.createTextTarget(marker, text)
                    end

                    if Markers.text[marker] then
                        local w, h = dxGetMaterialSize(Markers.text[marker])
                        w, h = w * 0.005 / 1.2, h * 0.005 / 1.2

                        drawTransformedMaterial(Markers.text[marker], x, y, z + 1.32 + anim, -90, -180 + camRy, camRz, w, h, { 255, 255, 255, alpha }, 0, 0, 0)
                    end
                end
            end
        end
    end
end

Markers.handleGroundAnimation = function(marker, x, y, z, size, r, g, b, alpha, tick)
    if not Markers.grounds[marker] then
        Markers.grounds[marker] = {}
        for idx = 1, GROUND_COUNT do
            Markers.grounds[marker][idx] = { value = 0, tick = tick - 1000 * idx }
        end
    else
        for idx = 1, GROUND_COUNT do
            local ground = Markers.grounds[marker][idx]
            local progress = (tick - ground.tick) / (GROUND_COUNT * 1000)
            if progress >= 0 then
                ground.value = interpolateBetween(0, 0, 0, 1, 0, 0, progress, 'OutQuad')

                if progress >= 1 then
                    ground.tick = tick
                    ground.value = 0
                end

                local sz = (size * ground.value) / 2
                dxDrawMaterialLine3D(x - sz, y, z, x + sz, y, z, Markers.textures['ground'], sz * 2, tocolor(r, g, b, (255 * (1 - ground.value)) * (alpha / 255)), false, x, y, z + 0.5)
            end
        end
    end
end

local chuj = createMarker(1482.9521484375, -1741.4965820312, 13.546875 - 0.9, 'cylinder', 1, 255, 0, 0, 50)
setElementData(chuj, 'text', 'Testowy marker')
setElementData(chuj, 'icon', 'door')
setMarkerColor(chuj, 255, 50, 90, 0)


local chuj2 = createMarker(1502.9521484375, -1741.4965820312, 13.546875 - 0.9, 'cylinder', 1, 255, 0, 0, 50)
setElementData(chuj2, 'text', 'Testowy marker')
setMarkerColor(chuj2, 255, 50, 90, 0)
