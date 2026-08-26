-- Login-screen camera flythrough - a slow pan/rotate between a handful
-- of fixed world-space camera positions, running behind the CEF login
-- card (see AuthCard.tsx's own SmokeBackground `transparent` prop +
-- App.tsx's body { background-color: transparent } - the whole point of
-- both is that this camera is actually visible underneath the card, not
-- just a black canvas). Ported from a reference implementation the user
-- provided - same coordinates/timings/easing, restructured only to start/
-- stop off this project's own AUTH_BEGIN_AUTHENTICATION/SPAWN_SELECT_OPEN
-- events (see AuthUiClient.lua) instead of globally-called
-- startCameraMovement()/endCameraMovement() functions, and to use this
-- project's own AnimationManager (UiAnimation.lua) instead of the
-- reference's bare createAnimation/setTimer pair.
LoginCamera = LoginCamera or {}

local CAMERAS = {
    {
        start = { pos = Vector3(2003.5523681641, -1449.8708496094, 179.3498992919), rot = Vector3(0, 0, 70.91839599609) },
        finish = { pos = Vector3(1223.9947509766, -1863.9333496094, 157.92959594727), rot = Vector3(-10, 0, 340.86511230469) },
        time = 40000,
    },
    {
        start = { pos = Vector3(-271.17001342773, 231.1381072998, 53.978298187256), rot = Vector3(351.9677734375, 0, 214.92309570313) },
        finish = { pos = Vector3(396.51119995117, -450.8623046875, 106.87419891357), rot = Vector3(347.03881835938, 0, 37.859130859375) },
        time = 40000,
    },
    {
        start = { pos = Vector3(2021.6086425781, 1865.3211669922, 97.476699829102), rot = Vector3(348.50634765625, 0, 213.48217773438) },
        finish = { pos = Vector3(2480.784912109, 917.9423828125, 110.85289764404), rot = Vector3(348.88549804688, 0, 46.849670410156) },
        time = 40000,
    },
}

-- How long each fade-to-black/fade-from-black half of a camera-switch
-- transition takes - matches the reference's own two 3000ms
-- createAnimation calls plus its 3000ms setTimer gap between them.
local FADE_DURATION_MS = 3000
local CAMERA_FAR_CLIP = 2000

local screenW, screenH = guiGetScreenSize()

local running = false
local changing = false
local selectedCamera = 1
local startCameraTick = 0
local fadeAlpha = 0

local function renderCameraMovement()
    local now = getTickCount()

    local camera = getCamera()
    local cameraData = CAMERAS[selectedCamera]
    local progress = math.min(1, (now - startCameraTick) / cameraData.time)

    local x, y, z = interpolateBetween(
        cameraData.start.pos.x, cameraData.start.pos.y, cameraData.start.pos.z,
        cameraData.finish.pos.x, cameraData.finish.pos.y, cameraData.finish.pos.z,
        progress, "Linear"
    )
    local rx, ry, rz = interpolateBetween(
        cameraData.start.rot.x, cameraData.start.rot.y, cameraData.start.rot.z,
        cameraData.finish.rot.x, cameraData.finish.rot.y, cameraData.finish.rot.z,
        progress, "Linear"
    )

    setElementPosition(camera, x, y, z)
    setElementRotation(camera, rx, ry, rz)

    if progress > 0.85 then
        LoginCamera.advanceToNextCamera()
    end
end

local function renderCameraFade()
    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, fadeAlpha))
end

--- Fades to black, jumps to the next camera in CAMERAS (wrapping
--- around), then fades back in - mirrors the reference's own
--- changeCamera(), just driven by this project's AnimationManager
--- instead of a bare createAnimation/setTimer pair.
function LoginCamera.advanceToNextCamera()
    if changing then
        return
    end
    changing = true

    AnimationManager.create(0, 255, "InOutQuad", FADE_DURATION_MS, function(value)
        fadeAlpha = value
    end, function()
        setTimer(function()
            changing = false

            startCameraTick = getTickCount()
            selectedCamera = selectedCamera + 1
            if selectedCamera > #CAMERAS then
                selectedCamera = 1
            end

            AnimationManager.create(255, 0, "InOutQuad", FADE_DURATION_MS, function(value)
                fadeAlpha = value
            end)
        end, FADE_DURATION_MS, 1)
    end)
end

--- Starts the flythrough (a random camera, faded straight in - no
--- fade-to-black needed for the very first one since the CEF card itself
--- covers the initial jump) - idempotent, a second call while already
--- running is a no-op.
function LoginCamera.start()
    if running then
        return
    end
    running = true

    startCameraTick = getTickCount()
    selectedCamera = math.random(1, #CAMERAS)
    fadeAlpha = 0

    addEventHandler("onClientPreRender", root, renderCameraMovement)
    addEventHandler("onClientRender", root, renderCameraFade, true, 'high+9999')
    setFarClipDistance(CAMERA_FAR_CLIP)
end

--- Stops the flythrough and restores the camera to following the local
--- player (setCameraTarget), undoing setFarClipDistance. Safe to call
--- even if never started.
function LoginCamera.stop()
    if not running then
        return
    end
    running = false
    changing = false

    removeEventHandler("onClientPreRender", root, renderCameraMovement)
    removeEventHandler("onClientRender", root, renderCameraFade)
    resetFarClipDistance()
end

addEvent(Events.AUTH_BEGIN_AUTHENTICATION, true)
addEventHandler(Events.AUTH_BEGIN_AUTHENTICATION, root, LoginCamera.start)

-- NOT AUTH_SUCCESS_AUTHENTICATION - that fires immediately on a
-- successful login/register, INCLUDING when registration is about to
-- show the post-registration 2FA-setup step, which (see AuthCard.tsx's
-- own createEffect on authStore.phase()) still renders inside this same
-- CEF login card, just a different internal view. Stopping the camera
-- there cut the flythrough out from under a player who was still looking
-- at the login screen (mid 2FA-setup). SPAWN_SELECT_OPEN is the actual
-- moment the player leaves this screen for the spawn-select map (see
-- AuthUiController.lua's PLAYER_ACCOUNT_RESOLVED handler, which fires
-- both events back to back - SPAWN_SELECT_OPEN is the one that matters
-- for this camera).
addEvent(Events.SPAWN_SELECT_OPEN, true)
addEventHandler(Events.SPAWN_SELECT_OPEN, root, LoginCamera.stop)

addEventHandler("onClientResourceStop", resourceRoot, LoginCamera.stop)
