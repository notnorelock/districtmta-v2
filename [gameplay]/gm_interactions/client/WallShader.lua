-- @author norelock <github.com/notnorelock>
-- @project districtMTA

-- info: nie znajdziesz tutaj nic ciekawego, to tylko rysowanie obramówek XD

local sx, sy = guiGetScreenSize()

local target
local ground = {}
local shaders = {}

local color = { 1, 0.2, 0, 1 }
local enabled = false
local distance = 10
local specularPower = 0.7

local groundTexture

local GROUND_SIZE = distance / 1.25
local GROUND_COUNT = 2

local function createObjectWallEffect(object, optimized)
    if not shaders.objects[object] then
        if not optimized then
            shaders.objects[object] = dxCreateShader("assets/ped_wall_mrt.fx", 1, 0, true, "all")
        else
            shaders.objects[object] = dxCreateShader("assets/ped_wall.fx", 1, 0, true, "all")
        end

        dxSetShaderValue(shaders.objects[object], "secondRT", target)
        dxSetShaderValue(shaders.objects[object], "sColorizePed", color)
        dxSetShaderValue(shaders.objects[object], "sSpecularPower", specularPower)
        engineApplyShaderToWorldTexture(shaders.objects[object], "*", object)
    end
end

local function destroyObjectWallEffect(object)
    if not shaders.objects[object] then return end

    if isElement(object) then
        engineRemoveShaderFromWorldTexture(shaders.objects[object], "*", object)
    end
    destroyElement(shaders.objects[object])
    shaders.objects[object] = nil
end

local function _onClientPreRender()
    if not enabled then return end

    dxSetRenderTarget(target, true)
    dxSetRenderTarget()

    dxDrawImage(0, 0, sx, sy, shaders.post_edge)

    local px, py, pz = getElementPosition(localPlayer)
    if not ground[localPlayer] then
        ground[localPlayer] = {}

        for i = 1, GROUND_COUNT do
            ground[localPlayer][i] = { value = -1, tick = getTickCount() - 2000 * i }
        end
    else
        for i = 1, GROUND_COUNT do
            local g = ground[localPlayer][i]
            local progress = (getTickCount() - g.tick) / (GROUND_COUNT * 2000)

            if progress >= 0 then
                g.value = interpolateBetween(0, 0, 0, 1, 0, 0, progress, "OutQuad")

                if progress >= 1 then
                    g.tick = getTickCount()
                    g.value = 0
                end

                local size = (GROUND_SIZE * g.value) / 2
                dxDrawMaterialLine3D(px - size, py, pz - 0.9, px + size, py, pz - 0.9, groundTexture, size * 2, tocolor(255, 255, 255, 255 * (1 - g.value)), false, px, py, pz - 0.01)
            end
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    target = dxCreateRenderTarget(sx, sy, true)
    groundTexture = dxCreateTexture("assets/ground.png")

    shaders.objects = {}
    shaders.post_edge = dxCreateShader("assets/post_edge.fx")
    dxSetShaderValue(shaders.post_edge, "sTex0", target)
    dxSetShaderValue(shaders.post_edge, "sRes", sx, sy)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        destroyElement(target)
        target = nil

        destroyElement(groundTexture)
        groundTexture = nil

        destroyElement(shaders.post_edge)
        shaders.post_edge = nil

        if #shaders.objects > 0 then
            for k, v in pairs(shaders.objects) do
                destroyElement(v)
                shaders.objects[k] = nil
            end
        end

        shaders = {}
    end)

    addEventHandler("onClientElementDestroy", root, function()
        if shaders.objects and shaders.objects[source] then
            destroyObjectWallEffect(source)
        end
    end)
end)

function toggleWallShader(state, objects)
    if not state then
        if enabled then
            for k, v in pairs(shaders.objects) do
                destroyObjectWallEffect(k)
            end

            ground[localPlayer] = nil
            removeEventHandler("onClientPreRender", root, _onClientPreRender)
        end
        enabled = false
        return
    end

    if not enabled then
        enabled = true
        addEventHandler("onClientPreRender", root, _onClientPreRender)
    end

    local wanted = {}
    for _, o in pairs(objects) do
        wanted[o] = true
        if not shaders.objects[o] then
            createObjectWallEffect(o)
        end
    end

    for o in pairs(shaders.objects) do
        if not wanted[o] then
            destroyObjectWallEffect(o)
        end
    end
end

function isWallShaderEnabled()
    return enabled
end

function isShaderOnObject(object)
    return shaders.objects[object] ~= nil
end