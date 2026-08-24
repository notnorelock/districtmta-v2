SpeedoComponent = SpeedoComponent or {}

local function getUIScale()
    return exports.core_ui:getUIScale() or 1
end

local function getUIFont(name)
    return exports.core_ui:getUIFont(name)
end

local function readEngineState(vehicle)
    local ok, rpm, gear = pcall(function()
        return exports.bengines:getVehicleRPM(vehicle), exports.bengines:getVehicleGear(vehicle)
    end)
    if not ok then
        return nil, nil
    end
    return rpm, gear
end

local ICONS = {
    { name = "engine" },
    { name = "brake" },
    { name = "lights" },
}

--- @return table a new SpeedoComponent instance (a HUDComponent.new() with speedo-specific fields/methods added)
SpeedoComponent.new = function()
    local self = HUDComponent.new()
    self.componentType = "SpeedoComponent"
    self.visible = false

    local zoom = getUIScale()
    local screenW, screenH = guiGetScreenSize()

    self.width = 384 / zoom
    self.height = 390 / zoom
    self.posX = (screenW - self.width) - 20 / zoom
    self.posY = screenH - self.height - 10 / zoom

    self.textures = {}
    self.fonts = {}

    function self:loadResources()
        self.textures = {
            bars = dxCreateTexture("assets/speedo/bars.png"),
            numbers = dxCreateTexture("assets/speedo/numbers.png"),
            pointer = dxCreateTexture("assets/speedo/pointer.png"),
            icons = {
                brake = dxCreateTexture("assets/speedo/icons/brake_icon.png"),
                brake_active = dxCreateTexture("assets/speedo/icons/brake_icon_active.png"),
                engine = dxCreateTexture("assets/speedo/icons/engine_icon.png"),
                engine_active = dxCreateTexture("assets/speedo/icons/engine_icon_active.png"),
                lights = dxCreateTexture("assets/speedo/icons/lights_icon.png"),
                lights_active = dxCreateTexture("assets/speedo/icons/lights_icon_active.png"),
            },
        }

        self.fonts = {
            gears = getUIFont("semibold_normal"),
            speed = getUIFont("bold_big"),
            unit = getUIFont("semibold_normal"),
        }
    end

    self.fading = nil

    -- Set only by Bootstrap.lua's own setSpeedoVisible(false) (e.g.
    -- gm_worldmap's openMap() hiding the whole HUD) - update() below
    -- self-drives visibility from vehicle occupancy every frame, which
    -- would otherwise immediately re-show() the dial the very next
    -- frame after an external hide() call, since being in a vehicle
    -- doesn't change just because the world map opened on top of it.
    self.suppressed = false

    function self:show(duration)
        self.visible = true

        if duration and duration > 0 then
            self.fading = "in"
            self.alpha = 0
            AnimationManager.create(0, 1, "Linear", duration, function(value)
                self.alpha = value
            end, function()
                self.fading = nil
            end)
        else
            self.fading = nil
            self.alpha = 1
        end
    end

    function self:hide(duration)
        if duration and duration > 0 then
            self.fading = "out"
            AnimationManager.create(self.alpha, 0, "Linear", duration, function(value)
                self.alpha = value
            end, function()
                self.visible = false
                self.fading = nil
            end)
        else
            self.fading = nil
            self.alpha = 0
            self.visible = false
        end
    end

    function self:update()
        if self.suppressed then
            return
        end

        local vehicle = getPedOccupiedVehicle(localPlayer)

        if vehicle and not self.visible and self.fading ~= "in" then
            self:show(400)
        elseif not vehicle and self.visible and self.fading ~= "out" then
            self:hide(400)
        end
    end

    function self:render()
        if not self.visible then
            return
        end

        local vehicle = getPedOccupiedVehicle(localPlayer)
        if not vehicle then
            return
        end

        local rawRpm, gear = readEngineState(vehicle) or 0, 0
        local rpm = math.max(-165, math.min(90, math.max(0, math.min(310, ((rawRpm or 0) / 9000) * 310)) - 165))

        local speed = math.floor((Vector3(getElementVelocity(vehicle)) * 170).length)

        local alphaByte = 255 * self.alpha
        local x, y, w, h = self.posX, self.posY, self.width, self.height

        dxDrawImage(x, y, w, h, self.textures.bars, 0, 0, 0, tocolor(255, 255, 255, alphaByte))
        dxDrawImage(x, y, w, h, self.textures.numbers, 0, 0, 0, tocolor(255, 255, 255, alphaByte))

        local pointerW, pointerH = 40 / zoom, 320 / zoom
        local dialCenterX, dialCenterY = x + w / 2, y + h / 2
        dxDrawImage(
            dialCenterX - pointerW / 2, dialCenterY - pointerH / 2, pointerW, pointerH,
            self.textures.pointer, rpm, 0, 0,
            tocolor(255, 255, 255, alphaByte)
        )

        dxDrawText(gear, dialCenterX, dialCenterY, nil, nil, tocolor(255, 100, 100, alphaByte), 1 / zoom, self.fonts.gears, "center", "center")
        dxDrawText(string.format("%03.f", speed), x + 245 / zoom, y + 180 / zoom, w + x, h + y, tocolor(255, 255, 255, alphaByte), 1.2 / zoom, self.fonts.speed, "left", "center")
        dxDrawText("km/h", x + 246 / zoom, y + 240 / zoom, w + x, h + y, tocolor(255, 255, 255, alphaByte), 0.75 / zoom, self.fonts.unit, "left", "center")

        for key, icon in ipairs(ICONS) do
            local offset = (key - 1) * (35 / zoom)
            local active

            if icon.name == "engine" then
                active = getVehicleEngineState(vehicle) and "_active" or ""
            elseif icon.name == "brake" then
                active = isElementFrozen(vehicle) and "_active" or ""
            elseif icon.name == "lights" then
                active = getVehicleOverrideLights(vehicle) == 2 and "_active" or ""
            end

            dxDrawImage(x + 242 / zoom + offset, y + 330 / zoom, 38 / zoom, 28 / zoom, self.textures.icons[icon.name .. active], 0, 0, 0, tocolor(255, 255, 255, alphaByte))
        end
    end

    local baseDestroy = self.destroy
    function self:destroy()
        for _, texture in pairs(self.textures) do
            if isElement(texture) then
                destroyElement(texture)
            elseif type(texture) == "table" then
                for _, iconTexture in pairs(texture) do
                    if isElement(iconTexture) then
                        destroyElement(iconTexture)
                    end
                end
            end
        end
        self.textures = {}

        baseDestroy(self)
    end

    self:loadResources()

    if getElementData(localPlayer, ElementData.Player.SPAWNED) == true and getPedOccupiedVehicle(localPlayer) then
        self:show(0)
    end

    return self
end
