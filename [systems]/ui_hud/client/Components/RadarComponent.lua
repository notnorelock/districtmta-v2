-- Custom radar (own map texture/blips/zone name overlay, drawn to a
-- render target then composited each frame) replacing GTA's own built-in
-- radar - ported from an older, unrelated project's own Components/
-- radar.lua (MTA class()/instanceof()) to a plain constructor function,
-- matching this project's own style (see HUDComponent.lua's own module
-- comment). getUIFont routed to core_ui's real export (the original's
-- own RES_UI:getUIFont was never wired to a real resource - see this
-- file's own git history/PR description). getUIScale has no project
-- equivalent (no per-player UI-scale system exists) - fixed at 1.
-- getGPSData similarly has no project equivalent (no GPS/route system
-- exists yet) - renderGPSRoute is kept dead-code-ready for when one does,
-- gated on gpsRoad always being nil today (see getGPSData's own comment).
RadarComponent = RadarComponent or {}

local function getUIFont(name)
    return exports.core_ui:getUIFont(name)
end

local function getUIScale()
    return exports.core_ui:getUIScale() or 1
end

-- No GPS/route system exists in this project yet - kept as a stub
-- returning nil (never a road) rather than deleting renderGPSRoute
-- entirely, so wiring a future navigation system only means replacing
-- this one function's body, not re-adding the rendering logic.
local function getGPSData()
    return nil
end

local mathDeg, mathFloor, mathAbs, mathMin, mathMax = math.deg, math.floor, math.abs, math.min, math.max
local mathRad, mathCos, mathSin, mathSqrt = math.rad, math.cos, math.sin, math.sqrt

--- @return table a new RadarComponent instance (a HUDComponent.new() with radar-specific fields/methods added)
RadarComponent.new = function()
    local self = HUDComponent.new()
    self.componentType = "RadarComponent"
    self.visible = false

    local zoom = getUIScale()
    local screenW, screenH = guiGetScreenSize()

    self.config = {
        mapTexture = "assets/radar/map.png",
        mapMask = "assets/radar/mask.png",
        textureSize = 1536,
        mapWaterColor = { 45, 46, 50 },
        alpha = 240,
        blipSize = 25,
    }

    self.width = mathFloor(335 / zoom)
    self.height = mathFloor(210 / zoom)
    self.posX = 20
    self.posY = (screenH - 40 / zoom) - self.height

    self.zoom = 1.5
    self.targetZoom = 1.5
    self.minZoom = 1
    self.maxZoom = 2
    self.zoomSpeed = 0.05

    self.alpha = 0
    self.targetAlpha = 0

    self.offsetX = 0
    self.offsetY = 0

    self.renderTarget = nil
    self.mapTexture = nil
    self.blipTextures = {}

    self.currentZone = nil
    self.currentCity = nil
    self.zoneAlpha = 0
    self.zoneOffsetY = 30 / zoom
    self.zoneTargetOffsetY = 30 / zoom
    self.zoneShowTime = 5000
    self.zoneTimer = nil
    self.zoneAnimDuration = 600

    self.lastZoneCheck = 0
    self.zoneCheckInterval = 500

    self.blipCache = {}
    self.lastBlipUpdate = 0
    self.blipUpdateInterval = 100

    function self:loadResources()
        self.renderTarget = dxCreateRenderTarget(self.width, self.height)
        self.mapTexture = dxCreateTexture(self.config.mapTexture, "dxt1")

        dxSetTextureEdge(self.mapTexture, "border", tocolor(
            self.config.mapWaterColor[1],
            self.config.mapWaterColor[2],
            self.config.mapWaterColor[3],
            255
        ))

        self.blipTextures.arrow = dxCreateTexture("assets/radar/arrow.png")
        for i = 0, 63 do
            local path = "assets/radar/blips/" .. i .. ".png"
            if fileExists(path) then
                self.blipTextures[i] = dxCreateTexture(path, "dxt3")
            end
        end
    end

    function self:findRotation(x1, y1, x2, y2)
        local t = -mathDeg(math.atan2(x2 - x1, y2 - y1))
        if t < 0 then t = t + 360 end
        return t
    end

    function self:getPointFromDistanceRotation(x, y, dist, angle)
        local a = mathRad(90 - angle)
        local dx = mathCos(a) * dist
        local dy = mathSin(a) * dist
        return x + dx, y + dy
    end

    function self:getVehicleSpeed(vehicle)
        if isElement(vehicle) then
            local vx, vy, vz = getElementVelocity(vehicle)
            return mathSqrt(vx ^ 2 + vy ^ 2 + vz ^ 2) * 187.5
        end
        return 0
    end

    function self:getBlips(camZ, maxDist, worldW, worldH)
        local now = getTickCount()
        if now - self.lastBlipUpdate < self.blipUpdateInterval and #self.blipCache > 0 then
            return self.blipCache
        end

        self.lastBlipUpdate = now
        maxDist = maxDist or 300
        local blips = {}
        local px, py = getElementPosition(localPlayer)
        local playerDim = getElementDimension(localPlayer)

        for _, blip in pairs(getElementsByType("blip")) do
            if getElementDimension(blip) == playerDim then
                local bx, by = getElementPosition(blip)
                local actualDist = getDistanceBetweenPoints2D(px + self.offsetX, py + self.offsetY, bx, by)
                local blipIcon = getBlipIcon(blip)
                local isImportant = false

                if getBlipVisibleDistance(blip) > 1000 or blipIcon < 3 or blipIcon == 4 or blipIcon == 9 then
                    isImportant = true
                end

                if actualDist <= maxDist or isImportant then
                    local _, _, _, blipAlpha = getBlipColor(blip)
                    local r, g, b = 255, 255, 255

                    if blipIcon == 0 then
                        r, g, b = getBlipColor(blip)
                    end

                    local dist = actualDist / (6000 / ((worldW + worldH) / 2))
                    local rot = self:findRotation(bx, by, px + self.offsetX, py + self.offsetY) - camZ

                    blips[#blips + 1] = {
                        icon = blipIcon,
                        x = bx,
                        y = by,
                        distance = dist,
                        color = tocolor(r, g, b, blipAlpha),
                        rotation = rot,
                        element = blip,
                    }
                end
            end
        end

        local dist = getDistanceBetweenPoints2D(px + self.offsetX, py + self.offsetY, px, py) / (6000 / ((worldW + worldH) / 2))
        local rot = self:findRotation(px, py, px + self.offsetX, py + self.offsetY) - camZ

        blips[#blips + 1] = {
            icon = "arrow",
            x = px,
            y = py,
            distance = dist,
            color = tocolor(255, 255, 255, 255),
            rotation = rot,
            element = localPlayer,
        }

        self.blipCache = blips
        return blips
    end

    -- Overrides HUDComponent's own plain field-set setVisible - the
    -- radial menu convention here also drives targetAlpha, not just the
    -- visible flag (see show/hide's own animated alpha).
    function self:setVisible(visible)
        self.visible = visible
        self.targetAlpha = visible and 1 or 0
    end

    function self:toggle()
        self:setVisible(not self.visible)
    end

    function self:show(duration)
        self.visible = true
        self.targetAlpha = 1

        if duration and duration > 0 then
            AnimationManager.create(self.alpha, 1, "InOutQuad", duration, function(value)
                self.alpha = value
            end)
        else
            self.alpha = 1
        end
    end

    function self:hide(duration)
        self.targetAlpha = 0

        if duration and duration > 0 then
            AnimationManager.create(self.alpha, 0, "InOutQuad", duration, function(value)
                self.alpha = value
            end, function()
                self.visible = false
            end)
        else
            self.alpha = 0
            self.visible = false
        end
    end

    function self:isVisible()
        return self.visible
    end

    function self:getPosition()
        return self.posX, self.posY, self.width, self.height
    end

    function self:setZoom(zoomLevel)
        self.targetZoom = mathMax(self.minZoom, mathMin(self.maxZoom, zoomLevel))
    end

    function self:checkZoneChange()
        local x, y, z = getElementPosition(localPlayer)
        local zoneName = getZoneName(x, y, z, false)
        local cityName = getZoneName(x, y, z, true)

        if zoneName ~= self.currentZone or cityName ~= self.currentCity then
            self.currentZone = zoneName
            self.currentCity = cityName
            self:showZoneText()
        end
    end

    local function removeZoneAnimations(component)
        for i = #component.animations, 1, -1 do
            local anim = component.animations[i]
            if anim.isZoneAnim then
                AnimationManager.remove(anim)
                table.remove(component.animations, i)
            end
        end
    end

    function self:showZoneText()
        if isTimer(self.zoneTimer) then
            killTimer(self.zoneTimer)
        end

        removeZoneAnimations(self)

        local offsetAnim = AnimationManager.create(30 / zoom, 0, "OutBack", self.zoneAnimDuration, function(value)
            self.zoneOffsetY = value
        end)
        offsetAnim.isZoneAnim = true
        self.animations[#self.animations + 1] = offsetAnim

        local alphaAnim = AnimationManager.create(self.zoneAlpha, 1, "OutQuad", self.zoneAnimDuration, function(value)
            self.zoneAlpha = value
        end)
        alphaAnim.isZoneAnim = true
        self.animations[#self.animations + 1] = alphaAnim

        self.zoneTimer = setTimer(function()
            self:hideZoneText()
        end, self.zoneShowTime, 1)
    end

    function self:hideZoneText()
        removeZoneAnimations(self)

        local offsetAnim = AnimationManager.create(self.zoneOffsetY, 30 / zoom, "InBack", self.zoneAnimDuration, function(value)
            self.zoneOffsetY = value
        end)
        offsetAnim.isZoneAnim = true
        self.animations[#self.animations + 1] = offsetAnim

        local alphaAnim = AnimationManager.create(self.zoneAlpha, 0, "OutQuad", self.zoneAnimDuration, function(value)
            self.zoneAlpha = value
        end)
        alphaAnim.isZoneAnim = true
        self.animations[#self.animations + 1] = alphaAnim
    end

    function self:renderZoneTextInTarget()
        if self.zoneAlpha <= 0 then return end

        local zoneName = self.currentZone
        local cityName = self.currentCity and string.upper(self.currentCity) or nil
        if not zoneName or not cityName then return end

        local bottomY = self.height - 40 / zoom + self.zoneOffsetY

        dxDrawImage(0, 0, self.width, self.height, "assets/radar/location_glow.png", 0, 0, 0,
            tocolor(255, 255, 255, 220 * self.zoneAlpha))

        dxDrawText(cityName, 0, bottomY, self.width, bottomY,
            tocolor(250, 250, 250, 255 * self.zoneAlpha), 0.70 / zoom, getUIFont("bold_normal"), "center", "center")

        if zoneName ~= cityName then
            dxDrawText(zoneName, 0, bottomY + 18 / zoom, self.width, bottomY + 18 / zoom,
                tocolor(210, 210, 210, 255 * self.zoneAlpha), 0.55 / zoom, getUIFont("regular_normal"), "center", "center")
        end
    end

    function self:getPosInRadar(x, y, worldW, worldH)
        return x / (6000 / worldW), y / (6000 / worldH)
    end

    function self:renderGPSRoute(px, py, mapPX, mapPY, worldW, worldH, camZ, radarAlpha, gpsRoad)
        if not gpsRoad or #gpsRoad == 0 then return end

        local cX, cY = self.width / 2, self.height / 2
        local rot = mathRad(-camZ)
        local cos, sin = mathCos(rot), mathSin(rot)
        local lineColor = tocolor(79, 140, 240, 255 * radarAlpha)

        for i = 1, #gpsRoad - 1 do
            local node = gpsRoad[i]
            local nextNode = gpsRoad[i + 1]

            if node and nextNode then
                local x1, y1 = self:getPosInRadar(node.posX + self.offsetX - px, node.posY + self.offsetY - py, worldW, worldH)
                local x2, y2 = self:getPosInRadar(nextNode.posX + self.offsetX - px, nextNode.posY + self.offsetY - py, worldW, worldH)

                local rx1 = x1 * cos - y1 * sin
                local ry1 = x1 * sin + y1 * cos
                local rx2 = x2 * cos - y2 * sin
                local ry2 = x2 * sin + y2 * cos

                dxDrawLine(cX + rx1, cY - ry1, cX + rx2, cY - ry2, lineColor, 4, false)
            end
        end
    end

    function self:renderBlips(camZ, playerRotZ, worldW, worldH, radarAlpha)
        local left = self.posX
        local right = self.posX + self.width
        local top = self.posY
        local bottom = self.posY + self.height
        local maxDist = 350

        local cX, cY = (right + left) / 2, (top + bottom) / 2
        local toTop, toRight = cY - top, right - cX

        dxSetBlendMode("modulate_add")

        for _, blip in pairs(self:getBlips(camZ, maxDist, worldW, worldH)) do
            if self.blipTextures[blip.icon] then
                local bpx, bpy = self:getPointFromDistanceRotation(
                    cX, cY,
                    mathMin(blip.distance, mathSqrt(toTop ^ 2 + toRight ^ 2)),
                    blip.rotation
                )

                bpx = mathMax(left, mathMin(right, bpx))
                bpy = mathMax(top, mathMin(bottom, bpy))

                local blipSize = self.config.blipSize
                local rot = 0

                if blip.icon == "arrow" then
                    rot = camZ - playerRotZ
                    blipSize = 22
                end

                local a = blip.color % 256
                local b = mathFloor(blip.color / 256) % 256
                local g = mathFloor(blip.color / 65536) % 256
                local r = mathFloor(blip.color / 16777216) % 256
                local finalBlipColor = tocolor(r, g, b, a * radarAlpha)

                dxDrawImage(bpx - blipSize / 2, bpy - blipSize / 2, blipSize, blipSize,
                    self.blipTextures[blip.icon], rot, 0, 0, finalBlipColor)
            end
        end

        dxSetBlendMode("blend")
    end

    function self:update()
        if not self.visible then return end

        if mathAbs(self.zoom - self.targetZoom) > 0.01 then
            self.zoom = self.zoom + (self.targetZoom - self.zoom) * self.zoomSpeed
        else
            self.zoom = self.targetZoom
        end

        if #self.animations == 0 then
            if mathAbs(self.alpha - self.targetAlpha) > 0.01 then
                self.alpha = self.alpha + (self.targetAlpha - self.alpha) * 0.1
            else
                self.alpha = self.targetAlpha
            end
        end

        local now = getTickCount()
        if now - self.lastZoneCheck >= self.zoneCheckInterval then
            self.lastZoneCheck = now
            self:checkZoneChange()
        end
    end

    function self:render()
        if not self.visible or getElementInterior(localPlayer) ~= 0 then
            return
        end

        local vehicle = getPedOccupiedVehicle(localPlayer)
        local speedZoom = 0

        if vehicle then
            local speed = self:getVehicleSpeed(vehicle) / 100
            speed = mathMin(speed, 2)
            speedZoom = speed / 4
        end

        local tmpZoom = self.zoom - speedZoom
        tmpZoom = mathMax(self.minZoom, mathMin(self.maxZoom, tmpZoom))

        local worldW = self.config.textureSize * tmpZoom
        local worldH = self.config.textureSize * tmpZoom

        local px, py, pz = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        local mapPX, mapPY = self:getPosInRadar(px + self.offsetX, py + self.offsetY, worldW, worldH)
        local mapX, mapY = self.width / 2 - mapPX, self.height / 2 + mapPY
        local _, _, camZ = getElementRotation(getCamera())

        dxSetRenderTarget(self.renderTarget, true)
        dxDrawRectangle(0, 0, self.width, self.height, tocolor(
            self.config.mapWaterColor[1],
            self.config.mapWaterColor[2],
            self.config.mapWaterColor[3],
            self.config.alpha
        ))
        dxDrawImage(
            mapX - worldW / 2, mapY - worldH / 2, worldW, worldH,
            self.mapTexture, camZ, mapPX, -mapPY, tocolor(255, 255, 255, 255)
        )

        local gpsData = getGPSData()
        if gpsData and gpsData.road then
            self:renderGPSRoute(px, py, mapPX, mapPY, worldW, worldH, camZ, 1, gpsData.road)
        end

        dxDrawImage(0, 0, self.width, self.height, "assets/radar/mask.png")
        self:renderZoneTextInTarget()

        dxSetRenderTarget()

        if getKeyState("num_add") or getKeyState("num_sub") then
            local zoomChange = getKeyState("num_sub") and 0.01 or -0.01
            self:setZoom(self.targetZoom + zoomChange)
        end

        local finalAlpha = self.alpha
        dxDrawImage(self.posX, self.posY, self.width, self.height, self.renderTarget, 0, 0, 0,
            tocolor(255, 255, 255, 255 * finalAlpha))
        dxDrawImage(self.posX, self.posY, self.width, self.height, "assets/radar/stroke.png", 0, 0, 0,
            tocolor(255, 255, 255, 255 * finalAlpha))

        self:renderBlips(camZ, rz, worldW, worldH, finalAlpha)
    end

    local baseDestroy = self.destroy
    function self:destroy()
        if isTimer(self.zoneTimer) then
            killTimer(self.zoneTimer)
        end

        for k, v in pairs(self.blipTextures) do
            if isElement(v) then
                destroyElement(v)
            end
        end
        self.blipTextures = {}

        if isElement(self.renderTarget) then
            destroyElement(self.renderTarget)
        end
        if isElement(self.mapTexture) then
            destroyElement(self.mapTexture)
        end

        baseDestroy(self)
    end

    self:loadResources()
    self:show(500)

    return self
end
