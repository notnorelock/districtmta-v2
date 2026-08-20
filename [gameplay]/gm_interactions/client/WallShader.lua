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
end)

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

    engineRemoveShaderFromWorldTexture(shaders.objects[object], "*", object)
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

function toggleWallShader(state, objects)
    if state == enabled then return end
    enabled = state
    
    if not enabled then
        for k, v in pairs(shaders.objects) do
            destroyObjectWallEffect(k)
        end

        ground[localPlayer] = nil
    else
        for i, o in pairs(objects) do
            if not shaders.objects[o] then
                createObjectWallEffect(o)
            end
        end
    end

    _G[enabled and "addEventHandler" or "removeEventHandler"]("onClientPreRender", root, _onClientPreRender)
end

function isWallShaderEnabled()
    return enabled
end

function isShaderOnObject(object)
    return shaders.objects[object] ~= nil
end