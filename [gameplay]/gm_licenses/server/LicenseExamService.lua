-- Driving license exams: walk into a category's marker to open a CEF
-- info dialog (name/fee/description), clicking "Rozpocznij" pays the fee
-- and shows a theory quiz (LicenseQuizzes.lua) in the same dialog,
-- passing it auto-starts the practical driving exam - a server-defined
-- checkpoint route to a free-driving finish. Every fail condition in the
-- practical exam is server-verified (checkpoint order, the opening
-- stationary beat, damage, free-drive distance) - never trusts anything
-- the client reports, matching this project's server-authoritative
-- discipline elsewhere (see GroupDutyService.lua's own periodic-tick
-- duty-second accrual for the same "never trust the client's own
-- clock/position" precedent). Category config (fee/vehicle model/route)
-- is LicenseCategories.lua; only categories with a non-nil route get a
-- marker spawned.
LicenseExamService = LicenseExamService or {}

-- How long (ms) the exam vehicle stays frozen at the start, during which
-- the player is expected to turn on lights/engine/release the handbrake
-- (not separately verified - see the stationary-beat check below, which
-- only cares that the vehicle stays still) before the route begins.
local STATIONARY_WINDOW_MS = 4000
-- getElementVelocity magnitude above which the stationary-beat check
-- considers the vehicle "moving" - a small epsilon, not 0, since a
-- frozen vehicle can still report a tiny residual velocity.
local STATIONARY_SPEED_THRESHOLD = 0.05
-- How often the free-drive distance accumulator / stationary-beat
-- checks run - same cadence class as GroupDutyService's own duty tick.
local EXAM_TICK_INTERVAL_MS = 1000
-- How long a failed theory quiz blocks re-attempting that category - a
-- player who paid and failed can retry after this without paying again
-- IF they walk back in after it elapses (see pendingQuiz's own comment
-- for the case where they haven't failed yet, just wandered off mid-quiz).
local QUIZ_FAIL_COOLDOWN_MS = 30 * 60 * 1000
-- Step-by-step quiz: a SINGLE shared clock for the whole quiz (not a
-- per-question timer). Starts at this many ms the moment the quiz
-- begins; every answer submitted (regardless of correctness) extends it
-- by QUIZ_ANSWER_BONUS_MS. Reaching 0 at any point fails the ENTIRE
-- quiz immediately, not just the current question - server-authoritative
-- via pendingQuiz.deadlineTick, never trusts client timing (see
-- LICENSE_QUIZ_ANSWER's own handler and runExamTick's own timeout sweep).
local QUIZ_QUESTION_TIME_MS = 60 * 1000
local QUIZ_ANSWER_BONUS_MS = 8 * 1000

-- category marker element -> category key (Enums.LicenseCategory value)
local categoryMarkers = {}
-- category blip element -> category key - a persistent, world-visible
-- (visibleTo left default, unlike the per-player checkpoint blips) blip
-- at each category's own markerPosition, so a player can see where to
-- start an exam without walking up on it blind. Same reload()-driven
-- lifecycle as categoryMarkers.
local categoryBlips = {}
-- player -> category key they're currently standing inside the marker of
local playersInMarker = {}
-- player -> { [category] = getTickCount() the cooldown ends } - in-memory
-- only, same "doesn't need to survive a restart" reasoning as
-- VehicleStorageService.lua's own RETRIEVE_COOLDOWN_MS tracking.
local quizCooldowns = {}
-- player -> {
--   category, categoryConfig, route, poolIndexes,     -- full sampled set (unchanged once sampled)
--   currentQuestionIndex,   -- 1-based index into poolIndexes the player is CURRENTLY on
--   answerIndexes = {},     -- answers submitted so far, index-parallel to poolIndexes
--   deadlineTick,           -- the ONE shared clock's expiry tick (getTickCount()-based), extended by
--                           -- QUIZ_ANSWER_BONUS_MS on every answer - see runExamTick's own timeout sweep
-- }
-- once the fee has been paid and the quiz has started, until it's
-- graded (pass/fail) or times out or the player quits. Deliberately NOT
-- cleared on onMarkerLeave - the fee is already paid at this point, so
-- walking out of the marker mid-quiz must not strand the paid-for
-- attempt or force a second charge; walking back into the marker
-- re-opens the SAME in-progress quiz (current question + ticking clock)
-- instead of the info screen (see onMarkerHit below).
local pendingQuiz = {}

-- player -> session table while the PRACTICAL exam is in progress:
-- {
--   category, categoryConfig, route, vehicle, examiner,
--   checkpointColshape = nil,  -- the CURRENT target checkpoint's invisible server-side hit-detector - see activateCheckpoint.
--                              -- The VISIBLE marker+blip are drawn client-side (client/LicenseExamState.lua), not tracked here at all.
--   routeStarted = false,    -- flips true exactly once, when the stationary-start beat ends (see runExamTick) - separate
--                            -- from checkpointIndex on purpose: checkpointIndex only ever advances INSIDE onCheckpointHit
--                            -- itself (checkpoint 1 included), so it must stay 0 while checkpoint 1 is the active-but-not-yet-hit
--                            -- target; this flag is what runExamTick actually checks to know the beat already ended,
--                            -- so it doesn't re-run the end-of-beat activation every tick.
--   checkpointIndex = 0,     -- 0 = no checkpoint hit yet (still on checkpoint 1, whether or not routeStarted), 1..#checkpoints = that many hit, #checkpoints+1 = free-drive
--   freeDriveAccumulatedMeters = 0, lastSampledPosition = nil,
--   stationaryDeadlineTick = nil, tookDamageAlready = false, finished = false,
-- }
local examSessions = {}

--- @param player element
-- @param category string one of Enums.LicenseCategory
-- @return boolean true only if GRANTED and NOT currently suspended.
--         Synchronous, reads the already-suspension-filtered
--         ElementData.Player.LICENSES mirror rather than round-tripping
--         through LicenseBridge - a cross-resource caller (e.g. a future
--         gm_vehicles_interaction "needs license" gate) needs this to
--         answer instantly, same reasoning gm_groups' own
--         groupServiceCanUseVehicle gives for reading a synchronous
--         in-memory cache rather than the DB on a hot path.
function licenseServiceHasLicense(player, category)
    if not isElement(player) then
        return false
    end
    local licenses = getElementData(player, ElementData.Player.LICENSES)
    if type(licenses) ~= "table" then
        return false
    end
    for _, c in ipairs(licenses) do
        if c == category then
            return true
        end
    end
    return false
end

-- Category resolution order: C/D's own vehicleModels (explicit model-ID
-- lists) are checked BEFORE any category's vehicleTypes (broad class
-- match) - C/D's own real vehicles (trucks/buses) are still
-- getVehicleType() == "Automobile" same as any car, so checking B's
-- broader vehicleTypes first would misclassify every truck/bus as a
-- plain category-B car. See LicenseCategories.lua's own module comment.
local CATEGORY_CHECK_ORDER = { Enums.LicenseCategory.C, Enums.LicenseCategory.D, Enums.LicenseCategory.A, Enums.LicenseCategory.B }

--- @param model number a vehicle model id (getElementModel(vehicle))
-- @return string|nil the Enums.LicenseCategory this model requires to
--         drive, nil if it isn't covered by any category (e.g. a
--         bicycle/boat/aircraft - none of A/B/C/D apply, see
--         LicenseCategories.lua's own module comment) and therefore
--         needs no license at all.
function licenseServiceGetRequiredCategory(model)
    if type(model) ~= "number" then
        return nil
    end

    for _, category in ipairs(CATEGORY_CHECK_ORDER) do
        local config = LicenseCategories[category]
        if config then
            if config.vehicleModels and config.vehicleModels[model] then
                return category
            end
            if config.vehicleTypes then
                local ok, vehicleType = pcall(getVehicleTypeFromModel, model)
                if ok and vehicleType and config.vehicleTypes[vehicleType] then
                    return category
                end
            end
        end
    end

    return nil
end

--- Re-fetches every LicenseGrant for this account, filters out any
--- category with an active suspension, and mirrors the result into
--- ElementData.Player.LICENSES - see that key's own comment for the
--- presence-check convention. Sends a WARNING notification (reason +
--- formatted expiry) for any held-but-suspended category found, if the
--- player is currently online.
-- @param player element
local function resyncElementData(player)
    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    LicenseBridge.call("findGrantsByAccountId", { accountId }, function(ok, grantsOrError)
        if not ok then
            Logger.error("LicenseExamService", "Failed to load license grants", { accountId = accountId, error = tostring(grantsOrError) })
            return
        end

        if not isElement(player) then
            return
        end

        local nowSql = os.date("!%Y-%m-%d %H:%M:%S")
        local activeCategories = {}
        local pending = #grantsOrError
        if pending == 0 then
            removeElementData(player, ElementData.Player.LICENSES)
            return
        end

        for _, grant in ipairs(grantsOrError) do
            local category = grant.category
            LicenseBridge.call("findActiveSuspensions", { accountId, category, nowSql }, function(suspensionOk, suspensionsOrError)
                if suspensionOk and #suspensionsOrError == 0 then
                    activeCategories[#activeCategories + 1] = category
                elseif suspensionOk and isElement(player) then
                    local suspension = suspensionsOrError[1]
                    NotificationService.send(player, {
                        type = Enums.NotificationType.WARNING,
                        message = string.format(
                            "Twoje prawo jazdy kat. %s jest zawieszone do %s. Powód: %s",
                            category,
                            tostring(suspension.expires_at or "odwołania"),
                            tostring(suspension.reason or "nie podano")
                        ),
                    })
                end

                pending = pending - 1
                if pending <= 0 and isElement(player) then
                    if #activeCategories > 0 then
                        setElementData(player, ElementData.Player.LICENSES, activeCategories)
                    else
                        removeElementData(player, ElementData.Player.LICENSES)
                    end
                end
            end)
        end
    end)
end
LicenseExamService.resyncElementData = resyncElementData

--- @param session table
-- @return boolean
local function findSessionByVehicle(vehicle)
    for player, session in pairs(examSessions) do
        if session.vehicle == vehicle then
            return player, session
        end
    end
    return nil, nil
end

--- @param player element
-- @param objective string
-- @param remainingMeters number|nil
local function pushObjective(player, objective, remainingMeters)
    if not isElement(player) then
        return
    end
    triggerClientEvent(player, Events.LICENSE_EXAM_OBJECTIVE_UPDATED, resourceRoot, {
        objective = objective,
        remainingMeters = remainingMeters,
    })
end

--- Guards against double-finish (e.g. damage and free-drive-complete
--- firing in the same tick) by clearing examSessions[player] BEFORE
--- doing anything else.
-- @param player element
-- @param session table
-- @param result string "passed" | "failed"
-- @param reason string|nil
local function finishExam(player, session, result, reason)
    if examSessions[player] ~= session or session.finished then
        return
    end
    session.finished = true
    examSessions[player] = nil

    if isElement(player) and isPedInVehicle(player) then
        removePedFromVehicle(player)
    end

    if isElement(session.vehicle) then
        destroyElement(session.vehicle)
    end
    if isElement(session.examiner) then
        destroyElement(session.examiner)
    end
    if isElement(session.checkpointColshape) then
        destroyElement(session.checkpointColshape)
    end
    session.checkpointColshape = nil

    if isElement(player) then
        -- Clears whatever marker/blip the client is currently drawing
        -- for the checkpoint it never got to finish reaching - the
        -- mid-route case (onCheckpointHit advancing normally) doesn't
        -- need this, its own next activateCheckpoint call replaces the
        -- client's visual directly, see that function's own comment.
        triggerClientEvent(player, Events.LICENSE_EXAM_CHECKPOINT_CLEARED, resourceRoot)

        triggerClientEvent(player, Events.LICENSE_EXAM_RETURN_FADE_OUT, resourceRoot)

        -- Restores the player's OWN pre-exam position/rotation/interior/
        -- dimension (captured in beginPracticalExam), not the route's
        -- static returnPosition - that config value has no
        -- interior/dimension at all, so a player who started the exam
        -- from inside a building would otherwise get teleported to the
        -- marker's own outdoor position while still stuck in that
        -- interior/dimension.
        local preExam = session.preExam
        setTimer(function()
            if not isElement(player) then
                return
            end
            setElementInterior(player, preExam.interior)
            setElementDimension(player, preExam.dimension)
            setElementPosition(player, preExam.x, preExam.y, preExam.z)
            setElementRotation(player, 0, 0, preExam.heading)
            triggerClientEvent(player, Events.LICENSE_EXAM_RETURN_FADE_IN, resourceRoot)
        end, 500, 1)

        if result == "passed" then
            local accountId = PlayerService.getAccountId(player)
            if accountId then
                LicenseBridge.call("createGrant", { accountId, session.category }, function(ok, grantOrError)
                    if not ok then
                        Logger.error("LicenseExamService", "Failed to persist license grant", { accountId = accountId, category = session.category, error = tostring(grantOrError) })
                        return
                    end
                    resyncElementData(player)
                end)
            end
            NotificationService.send(player, {
                type = Enums.NotificationType.SUCCESS,
                message = "Zdałeś egzamin! Otrzymujesz " .. session.categoryConfig.name .. ".",
            })
        else
            NotificationService.send(player, {
                type = Enums.NotificationType.ERROR,
                message = reason or "Nie zdałeś egzaminu.",
            })
        end

        triggerClientEvent(player, Events.LICENSE_EXAM_ENDED, resourceRoot, { result = result, reason = reason })
    end
end

--- @param vehicle vehicle
local function applyExamHandling(vehicle)
    -- setVehicleHandling scales the vehicle's OWN default handling
    -- (getVehicleHandling read first) rather than hardcoded absolutes,
    -- so this works reasonably across different category vehicle models
    -- without per-model tuning in v1.
    local default = getVehicleHandling(vehicle)
    setVehicleHandling(vehicle, "maxVelocity", (default.maxVelocity or 200) * 0.5)
    setVehicleHandling(vehicle, "engineAcceleration", (default.engineAcceleration or 5) * 0.5)
    setVehicleHandling(vehicle, "tractionLoss", (default.tractionLoss or 1) * 1.5)
end

--- @param player element
-- @param session table
-- @param route table
local function beginFreeDrive(player, session, route)
    session.checkpointIndex = #route.checkpoints + 1
    session.freeDriveAccumulatedMeters = 0
    session.lastSampledPosition = { getElementPosition(session.vehicle) }
    pushObjective(player, string.format("Kontynuuj jazdę swobodną (0 / %dm)", route.freeDriveDistanceMeters), route.freeDriveDistanceMeters)
end

-- Colshape radius floor - some placeholder/real checkpoint radii could
-- end up small enough that a full-size vehicle doesn't reliably
-- register onColShapeHit while visually "near" the spot.
local MIN_CHECKPOINT_COLSHAPE_SIZE = 4

-- Forward-declared - activateCheckpoint and onCheckpointHit call each
-- other (advancing to checkpoint N+1 activates it, hitting it advances
-- again), so both need to exist as upvalues before either is defined.
local activateCheckpoint
local onCheckpointHit

--- Creates ONLY the CURRENT target checkpoint's hit-detector
-- (`route.checkpoints[index]`) - an invisible server-side colshape, the
-- sole authority on whether the vehicle has reached it (never trusts
-- the client for this). The VISIBLE marker+blip are NOT created here -
-- LicenseExamState.lua (client Lua) owns drawing those itself, private
-- to the examinee only, in response to the LICENSE_EXAM_CHECKPOINT_ACTIVATED
-- push this function fires - see that event's own comment in Events.lua
-- for why (a server-created marker has no visibility-scoping parameter,
-- unlike createBlip's own visibleTo, so a client-drawn marker is the
-- only way to make it private). Only ever ONE checkpoint colshape
-- exists at a time per session (the current target) - onCheckpointHit
-- destroys the previous one before this creates the next, rather than
-- having the whole remaining route "live" at once.
-- @param player element
-- @param session table
-- @param route table
-- @param index number 1-based index into route.checkpoints
activateCheckpoint = function(player, session, route, index)
    local cp = route.checkpoints[index]
    local size = math.max(cp.radius, MIN_CHECKPOINT_COLSHAPE_SIZE)

    local colshape = createColSphere(cp.position.x, cp.position.y, cp.position.z, size)
    session.checkpointColshape = colshape

    addEventHandler("onColShapeHit", colshape, function(hitElement, matchingDimension)
        if not matchingDimension or hitElement ~= session.vehicle then
            return
        end
        onCheckpointHit(player, session, route, index)
    end)

    triggerClientEvent(player, Events.LICENSE_EXAM_CHECKPOINT_ACTIVATED, resourceRoot, {
        position = { x = cp.position.x, y = cp.position.y, z = cp.position.z },
        radius = size,
    })
end

--- @param player element
-- @param session table
-- @param route table
-- @param hitIndex number
onCheckpointHit = function(player, session, route, hitIndex)
    -- Only the CURRENT target's colshape exists at any time (see
    -- activateCheckpoint's own comment) - this guards against a stale/
    -- duplicate event firing twice for an already-advanced-past
    -- colshape, since destroyElement below doesn't synchronously stop
    -- an event already queued for this same tick.
    if hitIndex ~= session.checkpointIndex + 1 then
        return
    end

    session.checkpointIndex = hitIndex

    local colshape = session.checkpointColshape
    if isElement(colshape) then
        destroyElement(colshape)
    end
    session.checkpointColshape = nil

    if hitIndex < #route.checkpoints then
        pushObjective(player, route.checkpoints[hitIndex + 1].objective)
        -- Only the NEXT checkpoint's colshape+visual appear now - not
        -- the whole remaining route at once, see activateCheckpoint's
        -- own comment. activateCheckpoint's own
        -- LICENSE_EXAM_CHECKPOINT_ACTIVATED push replaces whatever the
        -- client is currently drawing, so no separate "cleared" push is
        -- needed for this mid-route case - only finishExam (early
        -- termination/pass) needs LICENSE_EXAM_CHECKPOINT_CLEARED, since
        -- nothing else follows it up with a new ACTIVATED push there.
        activateCheckpoint(player, session, route, hitIndex + 1)
    else
        if isElement(player) then
            triggerClientEvent(player, Events.LICENSE_EXAM_CHECKPOINT_CLEARED, resourceRoot)
        end
        beginFreeDrive(player, session, route)
    end
end

-- Forward-declared - failQuiz's real definition sits further down
-- (needs LicenseQuizzes/Events in scope the same way every other
-- handler in this file does), but runExamTick below must be able to
-- call it as an upvalue; assigning to this same local later (not a
-- second `local function failQuiz`) is what makes that visible here.
local failQuiz

--- Periodic tick: free-drive distance accumulation, the opening
-- stationary-beat fail check, and the shared quiz clock timeout sweep.
-- All server-observable/server-owned only.
local examTickTimer = nil
local function runExamTick()
    for player, pending in pairs(pendingQuiz) do
        if not isElement(player) then
            pendingQuiz[player] = nil
        elseif getTickCount() > pending.deadlineTick then
            failQuiz(player, pending)
        end
    end

    for player, session in pairs(examSessions) do
        if not isElement(player) or not isElement(session.vehicle) then
            -- Defensive - onPlayerQuit/vehicle destruction should already
            -- have finished this session, but never leave a dangling
            -- entry ticking forever.
            examSessions[player] = nil
        elseif not session.routeStarted then
            if getTickCount() > session.stationaryDeadlineTick then
                session.routeStarted = true
                setElementFrozen(session.vehicle, false)
                -- session.checkpointIndex is deliberately LEFT at 0 here
                -- (not bumped to 1) - onCheckpointHit's own guard expects
                -- "checkpointIndex + 1 == hitIndex" to accept a hit, the
                -- exact same contract every LATER checkpoint relies on
                -- (checkpointIndex only advances INSIDE onCheckpointHit
                -- itself, once the marker is actually reached). Bumping it
                -- here too was a real bug: it made onCheckpointHit's own
                -- guard reject checkpoint 1's hit outright (checking
                -- 1 == 1+1), which is why nothing ever advanced no matter
                -- how many times the first checkpoint was driven through.
                -- routeStarted (checked above, not checkpointIndex) is
                -- what stops this branch from re-running every tick now
                -- that checkpointIndex itself stays 0 through all of checkpoint 1.
                pushObjective(player, session.route.checkpoints[1].objective)
                -- First checkpoint's marker+blip appear exactly when they
                -- become the active target (vehicle unfreezes) - not
                -- upfront at exam start, see activateCheckpoint's own
                -- comment on why only one exists at a time.
                activateCheckpoint(player, session, session.route, 1)
            else
                -- Reads the vehicle's OWN server-synced velocity directly,
                -- never anything client-reported - the vehicle is ALSO
                -- frozen server-side during this beat (see beginPracticalExam),
                -- so this is defense-in-depth against a frozen-state desync,
                -- not the primary mechanism.
                local vx, vy, vz = getElementVelocity(session.vehicle)
                local speed = (vx * vx + vy * vy + vz * vz) ^ 0.5
                if speed > STATIONARY_SPEED_THRESHOLD then
                    finishExam(player, session, "failed", "Ruszyłeś pojazdem przed sygnałem instruktora.")
                end
            end
        elseif session.checkpointIndex > #session.route.checkpoints then
            local x, y, z = getElementPosition(session.vehicle)
            local last = session.lastSampledPosition
            local delta = getDistanceBetweenPoints3D(x, y, z, last[1], last[2], last[3])
            session.freeDriveAccumulatedMeters = session.freeDriveAccumulatedMeters + delta
            session.lastSampledPosition = { x, y, z }

            local target = session.route.freeDriveDistanceMeters
            if session.freeDriveAccumulatedMeters >= target then
                finishExam(player, session, "passed", nil)
            else
                pushObjective(
                    player,
                    string.format("Kontynuuj jazdę swobodną (%d / %dm)", math.floor(session.freeDriveAccumulatedMeters), target),
                    target - session.freeDriveAccumulatedMeters
                )
            end
        end
    end
end

--- Unlike gm_vehicles_interaction's own onVehicleStartEnter (which only
-- gates the driver seat, always letting a passenger ride along), this
-- blocks EVERY seat: an exam vehicle has exactly two legitimate
-- occupants (the examinee and the examiner ped), both warped in
-- programmatically at exam start (warpPedIntoVehicle never fires this
-- event) - so the only player who can ever physically reach this
-- handler, in any seat, on a tracked exam vehicle, is an uninvited
-- third party.
-- @param player element
-- @param seat number
local function onExamVehicleStartEnter(player, seat)
    local _, session = findSessionByVehicle(source)
    if not session then
        return
    end
    cancelEvent()
end

--- @param player element
local function onExamVehicleStartExit(player)
    local sessionPlayer, session = findSessionByVehicle(source)
    if not session or sessionPlayer ~= player then
        return
    end
    -- Prevents dodging a fail by exiting mid-exam. finishExam's own
    -- removePedFromVehicle call (legitimate end-of-exam removal) is
    -- an unconditional server-side teleport-out, not a player-pressed
    -- exit, and empirically does not re-enter this handler.
    cancelEvent()
end

--- @param attacker element|nil
-- @param weapon number|nil
-- @param bodypart number|nil
-- @param loss number|nil
local function onExamVehicleDamage(attacker, weapon, bodypart, loss)
    local player, session = findSessionByVehicle(source)
    if not session then
        return
    end

    -- Cancel unconditionally - the exam vehicle never visibly takes
    -- damage (matches the reference script's own cancel-for-external
    -- behavior). Fail unconditionally on the FIRST hit regardless of
    -- attacker - deliberately simplified from the reference script's
    -- attacker-classification (which cannot cleanly separate "you
    -- crashed" from "someone hit you" from attacker/bodypart alone; any
    -- meaningful damage during an active exam is disqualifying in a real
    -- driving exam anyway).
    cancelEvent()
    if not session.tookDamageAlready then
        session.tookDamageAlready = true
        finishExam(player, session, "failed", "Pojazd uległ uszkodzeniu podczas egzaminu.")
    end
end

--- @param player element
-- @return boolean, string|nil ok, errorMessage
local function checkEligibility(player, category)
    if examSessions[player] then
        return false, "Jesteś już w trakcie egzaminu."
    end
    if licenseServiceHasLicense(player, category) then
        return false, "Posiadasz już to prawo jazdy."
    end
    return true, nil
end

--- @param player element
-- @param category string
-- @return number secondsRemaining, 0 if not on cooldown (or it already elapsed)
local function cooldownRemainingSeconds(player, category)
    local playerCooldowns = quizCooldowns[player]
    if not playerCooldowns or not playerCooldowns[category] then
        return 0
    end
    local remainingMs = playerCooldowns[category] - getTickCount()
    if remainingMs <= 0 then
        playerCooldowns[category] = nil
        return 0
    end
    return math.ceil(remainingMs / 1000)
end

--- Spawns the exam vehicle/examiner/checkpoints and pushes
-- LICENSE_EXAM_STARTED - the practical-exam half of what used to be the
-- single /startexam function, now only reached after a paid, passed
-- quiz (LICENSE_QUIZ_ANSWER's own final-question pass branch below).
-- @param player element
-- @param category string
-- @param categoryConfig table LicenseCategories[category]
-- @param route table categoryConfig.route
local function beginPracticalExam(player, category, categoryConfig, route)
    -- Captured BEFORE warping into the exam vehicle - restored verbatim
    -- in finishExam below, instead of the route's own static
    -- returnPosition (which has no interior/dimension at all, and puts
    -- every finish at the marker regardless of where the player actually
    -- started from - e.g. inside a building's own interior/dimension).
    local preExamX, preExamY, preExamZ = getElementPosition(player)
    local _, _, preExamHeading = getElementRotation(player)
    local preExam = {
        x = preExamX, y = preExamY, z = preExamZ,
        heading = preExamHeading,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
    }

    local startPos = route.startPosition
    -- heading in the 3rd rotation arg (rz), never rx/ry - confirmed
    -- project-wide convention (see AdminCommands.lua's own store
    -- spawn-position fix earlier in this project's history).
    local vehicle = createVehicle(categoryConfig.vehicleModel, startPos.x, startPos.y, startPos.z, 0, 0, startPos.heading or 0)
    if not vehicle then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się stworzyć pojazdu egzaminacyjnego. Zgłoś to administratorowi." })
        return
    end

    setElementFrozen(vehicle, true)
    setElementData(vehicle, ElementData.Vehicle.EXAM_VEHICLE, true)
    applyExamHandling(vehicle)
    warpPedIntoVehicle(player, vehicle, 0)

    local examiner = createPed(route.examinerSkin or 264, startPos.x, startPos.y, startPos.z)
    warpPedIntoVehicle(examiner, vehicle, 1)

    local session = {
        category = category,
        categoryConfig = categoryConfig,
        route = route,
        vehicle = vehicle,
        examiner = examiner,
        checkpointColshape = nil,
        routeStarted = false,
        checkpointIndex = 0,
        freeDriveAccumulatedMeters = 0,
        lastSampledPosition = nil,
        stationaryDeadlineTick = getTickCount() + STATIONARY_WINDOW_MS,
        tookDamageAlready = false,
        finished = false,
        preExam = preExam,
    }
    examSessions[player] = session

    -- No upfront checkpoint creation - the first checkpoint's marker+blip
    -- only appear once the stationary-start beat ends (runExamTick's own
    -- routeStarted transition activates checkpoint 1), matching the
    -- step-by-step "only the current target exists" design throughout.

    triggerClientEvent(player, Events.LICENSE_EXAM_STARTED, resourceRoot, {
        category = category,
        categoryName = categoryConfig.name,
        objective = "Poczekaj na sygnał instruktora i nie ruszaj pojazdem.",
    })

    Logger.info("LicenseExamService", "Practical exam started", { player = getPlayerName(player), category = category })
end

--- Builds the single-question push payload for `pending`'s CURRENT
-- question (pending.currentQuestionIndex) - shared by the dialog-start
-- handler, onMarkerHit's own quiz-reopen branch, and the answer
-- handler's "advance to next question" push, so all three send an
-- identical shape.
-- @param pending table pendingQuiz[player]
-- @param player element|nil - only needed for the DEBUG output below (kept at the user's request)
-- @return table { category, questionNumber, totalQuestions, question, remainingSeconds }
local function buildQuestionPushPayload(pending, player)
    local poolIndex = pending.poolIndexes[pending.currentQuestionIndex]

    -- DEBUG (kept at the user's explicit request) - chat-prints the
    -- correct answer for whichever question is currently being sent.
    if isElement(player) then
        local correctIndex, correctText = LicenseQuizzes.debugCorrectAnswer(pending.category, poolIndex)
        if correctIndex then
            outputChatBox(string.format(
                "[DEBUG quiz %d/%d] Poprawna: checkbox #%d -> \"%s\"",
                pending.currentQuestionIndex, #pending.poolIndexes, correctIndex, tostring(correctText)
            ), player)
        end
    end

    return {
        category = pending.category,
        questionNumber = pending.currentQuestionIndex,
        totalQuestions = #pending.poolIndexes,
        question = LicenseQuizzes.toClientQuestions(pending.category, { poolIndex })[1],
        remainingSeconds = math.max(0, math.ceil((pending.deadlineTick - getTickCount()) / 1000)),
    }
end

--- @param category string
-- @param player element
local function onMarkerHit(category, player)
    playersInMarker[player] = category

    if examSessions[player] then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Jesteś już w trakcie egzaminu." })
        return
    end

    -- Re-opens the SAME in-progress quiz (already paid for) rather than
    -- the info screen - see pendingQuiz's own comment on why it isn't
    -- cleared on marker-leave. The shared clock (deadlineTick) has kept
    -- counting down the whole time the player was away, so the re-sent
    -- remainingSeconds reflects that honestly, never resets/pauses.
    local pending = pendingQuiz[player]
    if pending and pending.category == category then
        triggerClientEvent(player, Events.LICENSE_QUIZ_QUESTIONS_RECEIVED, resourceRoot, buildQuestionPushPayload(pending, player))
        return
    end

    if licenseServiceHasLicense(player, category) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Posiadasz już to prawo jazdy." })
        return
    end

    local categoryConfig = LicenseCategories[category]
    triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_OPEN, resourceRoot, {
        category = category,
        categoryName = categoryConfig.name,
        fee = categoryConfig.fee or 0,
        cooldownRemainingSeconds = cooldownRemainingSeconds(player, category),
    })
end

local function onMarkerLeave(player)
    playersInMarker[player] = nil
    -- Only close the dialog if the fee hasn't been paid yet (no pending
    -- quiz) - once paid, the quiz stays open server-side (pendingQuiz)
    -- and the CEF panel itself decides whether to keep showing until the
    -- player submits or walks back in, matching VehicleStorageService.lua's
    -- own onLeaveStore closing the panel for the pre-commitment case only.
    if not pendingQuiz[player] then
        triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
    end
end

--- Player clicked "Rozpocznij" on the info screen - re-validates
-- everything server-side (never trusts the dialog was shown correctly),
-- takes the fee, samples a quiz, and sends it back.
addEvent(Events.LICENSE_EXAM_DIALOG_START, true)
addEventHandler(Events.LICENSE_EXAM_DIALOG_START, root, function(category)
    local player = client
    if type(category) ~= "string" or not Enums.LicenseCategory[category] then
        return
    end

    local eligibleOk, eligibleError = checkEligibility(player, category)
    if not eligibleOk then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = eligibleError })
        triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
        return
    end

    local remaining = cooldownRemainingSeconds(player, category)
    if remaining > 0 then
        NotificationService.send(player, { type = Enums.NotificationType.WARNING, message = "Musisz poczekać przed kolejną próbą (" .. math.ceil(remaining / 60) .. " min)." })
        return
    end

    local categoryConfig = LicenseCategories[category]
    local route = categoryConfig and categoryConfig.route
    if not route then
        -- Should never happen (no marker gets created for a route = nil
        -- category - see reload() below), defensive only.
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Ta kategoria nie jest jeszcze dostępna." })
        return
    end

    if not LicenseQuizzes.hasPool(category) then
        NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Test teoretyczny dla tej kategorii nie jest jeszcze dostępny." })
        return
    end

    local accountId = PlayerService.getAccountId(player)
    if not accountId then
        return
    end

    -- Re-check suspension separately via LicenseBridge - the
    -- authoritative check for this one gate (the ElementData mirror
    -- could be stale until the next login-time resync).
    local nowSql = os.date("!%Y-%m-%d %H:%M:%S")
    LicenseBridge.call("findActiveSuspensions", { accountId, category, nowSql }, function(ok, suspensionsOrError)
        if not isElement(player) then
            return
        end
        if not ok then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie udało się zweryfikować uprawnień. Spróbuj ponownie." })
            return
        end
        if #suspensionsOrError > 0 then
            local suspension = suspensionsOrError[1]
            NotificationService.send(player, {
                type = Enums.NotificationType.ERROR,
                message = string.format("Twoje uprawnienia do tej kategorii są zawieszone do %s.", tostring(suspension.expires_at or "odwołania")),
            })
            triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
            return
        end

        -- Re-check eligibility once more (race window between the
        -- button click and this async suspension check).
        local eligibleOk2, eligibleError2 = checkEligibility(player, category)
        if not eligibleOk2 then
            NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = eligibleError2 })
            triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
            return
        end

        local fee = categoryConfig.fee or 0
        if fee > 0 then
            -- Required pre-check: takeMoney floors at 0 server-side with
            -- no rejection signal, so affordability must be verified
            -- BEFORE calling it.
            local money = PlayerService.getMoney(player)
            if not money or money < fee then
                NotificationService.send(player, { type = Enums.NotificationType.ERROR, message = "Nie stać cię na ten egzamin (koszt: " .. fee .. " zł)." })
                return
            end
            pcall(function() PlayerService.takeMoney(player, fee) end)
        end

        local poolIndexes = LicenseQuizzes.sample(category)
        local pending = {
            category = category,
            categoryConfig = categoryConfig,
            route = route,
            poolIndexes = poolIndexes,
            currentQuestionIndex = 1,
            answerIndexes = {},
            deadlineTick = getTickCount() + QUIZ_QUESTION_TIME_MS,
        }
        pendingQuiz[player] = pending

        triggerClientEvent(player, Events.LICENSE_QUIZ_QUESTIONS_RECEIVED, resourceRoot, buildQuestionPushPayload(pending, player))
    end)
end)

--- Shared by both the late-answer guard below and runExamTick's own
-- timeout sweep - the shared quiz clock ran out, fail the WHOLE quiz
-- (not just the current question) and apply the retry cooldown.
-- Assigns the forward-declared `failQuiz` local above (NOT `local
-- function failQuiz`, which would shadow it with a second, separate
-- local) so runExamTick's own upvalue reference resolves correctly.
-- @param player element
-- @param pending table pendingQuiz[player]
failQuiz = function(player, pending)
    pendingQuiz[player] = nil
    quizCooldowns[player] = quizCooldowns[player] or {}
    quizCooldowns[player][pending.category] = getTickCount() + QUIZ_FAIL_COOLDOWN_MS
    if isElement(player) then
        -- The CEF dialog closes IMMEDIATELY (see LICENSE_EXAM_DIALOG_CLOSE
        -- right below) - there's no time for its own in-panel result text
        -- to be read, so the actual feedback goes through the same native
        -- NotificationService toast every other pass/fail moment in this
        -- exam system already uses (checkpoint fails, practical exam
        -- pass/fail - see finishExam's own NotificationService.send calls),
        -- not text rendered inside the closing panel.
        NotificationService.send(player, {
            type = Enums.NotificationType.ERROR,
            message = "Nie zdążyłeś odpowiedzieć na czas. Spróbuj ponownie za 30 minut.",
        })
        triggerClientEvent(player, Events.LICENSE_QUIZ_RESULT, resourceRoot, { passed = false, timedOut = true })
        triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
    end
end

--- Player answered the CURRENT question only (not a batch) - extends
-- the shared clock, advances to the next question, or grades the full
-- set if this was the last one. Grades against the SERVER's own
-- remembered sampled set (pendingQuiz), never the client's claim.
addEvent(Events.LICENSE_QUIZ_ANSWER, true)
addEventHandler(Events.LICENSE_QUIZ_ANSWER, root, function(category, answerIndex)
    local player = client
    local pending = pendingQuiz[player]
    if not pending or pending.category ~= category then
        return
    end

    -- Re-validates the shared clock server-side FIRST - a client that
    -- waited past its own locally-rendered 0:00 and only THEN fired this
    -- event must still be rejected/failed, never trust client timing.
    if getTickCount() > pending.deadlineTick then
        failQuiz(player, pending)
        return
    end

    pending.answerIndexes[pending.currentQuestionIndex] = answerIndex
    pending.deadlineTick = pending.deadlineTick + QUIZ_ANSWER_BONUS_MS
    pending.currentQuestionIndex = pending.currentQuestionIndex + 1

    if pending.currentQuestionIndex > #pending.poolIndexes then
        local passed, correctCount, totalCount = LicenseQuizzes.grade(category, pending.poolIndexes, pending.answerIndexes)
        pendingQuiz[player] = nil

        if passed then
            NotificationService.send(player, {
                type = Enums.NotificationType.SUCCESS,
                message = string.format("Zaliczono test teoretyczny! (%d/%d) Rozpoczynasz część praktyczną.", correctCount, totalCount),
            })
            triggerClientEvent(player, Events.LICENSE_QUIZ_RESULT, resourceRoot, { passed = true, correctCount = correctCount, totalCount = totalCount })
            -- Closes the dialog overlay before handing off to the
            -- practical exam's own HUD (LicenseExamHud.tsx) - without
            -- this the "licenseExam" Overlay stays technically visible
            -- (just rendering nothing) until something else hides it.
            triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
            beginPracticalExam(player, pending.category, pending.categoryConfig, pending.route)
        else
            quizCooldowns[player] = quizCooldowns[player] or {}
            quizCooldowns[player][category] = getTickCount() + QUIZ_FAIL_COOLDOWN_MS
            NotificationService.send(player, {
                type = Enums.NotificationType.ERROR,
                message = string.format("Nie zaliczono testu teoretycznego (%d/%d). Spróbuj ponownie za 30 minut.", correctCount, totalCount),
            })
            triggerClientEvent(player, Events.LICENSE_QUIZ_RESULT, resourceRoot, { passed = false, correctCount = correctCount, totalCount = totalCount })
            triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
        end
        return
    end

    -- More questions remain - push the next one plus the freshly-extended clock.
    triggerClientEvent(player, Events.LICENSE_QUIZ_QUESTIONS_RECEIVED, resourceRoot, buildQuestionPushPayload(pending, player))
end)

addEventHandler("onPlayerQuit", root, function()
    local session = examSessions[source]
    if session then
        finishExam(source, session, "failed", "Egzamin przerwany.")
    end
    playersInMarker[source] = nil
    pendingQuiz[source] = nil
    quizCooldowns[source] = nil
end)

-- Must be locally re-declared with addEvent even though core already
-- declares it - every resource needs its own addEvent for a custom
-- event before it can receive it, see gm_items/server/InventoryLifecycle.lua's
-- own identical PLAYER_ACCOUNT_RESOLVED registration for the precedent.
addEvent(Events.PLAYER_ACCOUNT_RESOLVED, true)
addEventHandler(Events.PLAYER_ACCOUNT_RESOLVED, root, function(account)
    if type(account) ~= "table" or type(account.id) ~= "number" then
        return
    end
    resyncElementData(source)
end)

--- Destroys every currently-spawned category marker and re-creates them
-- from LicenseCategories.lua - only categories with a non-nil route get
-- a marker. Called once at startup; no live-reload trigger exists yet
-- since LicenseCategories.lua is static Lua config, not a database
-- table (unlike gm_groups' own duty markers).
local function reload()
    for marker in pairs(categoryMarkers) do
        if isElement(marker) then
            destroyElement(marker)
        end
    end
    categoryMarkers = {}

    for blip in pairs(categoryBlips) do
        if isElement(blip) then
            destroyElement(blip)
        end
    end
    categoryBlips = {}

    for category, config in pairs(LicenseCategories) do
        if config.route then
            local pos = config.route.markerPosition
            local marker = createMarker(pos.x, pos.y, pos.z - 0.9, "cylinder", 1.5, 30, 144, 255, 100)
            setElementInterior(marker, pos.interior or 0)
            setElementDimension(marker, pos.dimension or 0)
            setElementData(marker, "text", config.name)
            categoryMarkers[marker] = category

            -- Icon 0 (default GTA:SA radar dot) - the earlier icon 32
            -- ("Test Track" sprite) turned out not to render at all in
            -- practice (confirmed live: not one of the sprite IDs MTA
            -- actually ships an icon for), so this uses the one icon ID
            -- guaranteed to always show something (every existing blip
            -- usage in this codebase - PlayerBlips.lua's own
            -- BLIP_ICON_DEFAULT - relies on the same default/0 icon).
            -- size 2 + explicit bright color so it's easy to pick out
            -- from a real player blip. Visible to everyone by default
            -- (createBlip's own visibleTo omitted) - unlike this, the
            -- per-checkpoint marker/blip during an active exam are drawn
            -- entirely client-side (client/LicenseExamState.lua), private
            -- to the examinee only, see activateCheckpoint's own comment.
            local blip = createBlip(pos.x, pos.y, pos.z, 0, 2, 30, 144, 255, 255)
            setElementInterior(blip, pos.interior or 0)
            setElementDimension(blip, pos.dimension or 0)
            categoryBlips[blip] = category

            addEventHandler("onMarkerHit", marker, function(hitElement, matchingDimension)
                if getElementType(hitElement) ~= "player" or not matchingDimension then
                    return
                end
                onMarkerHit(category, hitElement)
            end)

            addEventHandler("onMarkerLeave", marker, function(hitElement, matchingDimension)
                if getElementType(hitElement) ~= "player" or not matchingDimension then
                    return
                end
                onMarkerLeave(hitElement)
            end)
        end
    end

    if isTimer(examTickTimer) then
        killTimer(examTickTimer)
    end
    examTickTimer = setTimer(runExamTick, EXAM_TICK_INTERVAL_MS, 0)

    addEventHandler("onVehicleStartEnter", root, onExamVehicleStartEnter)
    addEventHandler("onVehicleStartExit", root, onExamVehicleStartExit)
    addEventHandler("onVehicleDamage", root, onExamVehicleDamage)

    Logger.info("LicenseExamService", "Loaded license categories", { count = 4 })
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Same DATABASE_READY/schemaIsMigrated gotcha VehicleStorageService.lua/
    -- GroupDutyService.lua both document - a fresh table sorted late can
    -- still be mid-CREATE TABLE when this resource's own onResourceStart fires.
    local migratedOk, migrated = pcall(function() return exports.core:schemaIsMigrated() end)
    if migratedOk and migrated then
        reload()
    else
        addEvent(Events.DATABASE_READY, true)
        addEventHandler(Events.DATABASE_READY, root, reload)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, session in pairs(examSessions) do
        finishExam(player, session, "failed", "Egzamin przerwany (restart zasobu).")
    end

    -- Closes any open quiz dialog too, so a restart mid-quiz doesn't
    -- leave a player staring at a frozen CEF panel with a clock that
    -- will never resume ticking (the client-side ticker in
    -- LicenseExamState.lua stops on its own via onClientResourceStop,
    -- but only the server closing the dialog actually clears
    -- pendingQuiz and applies/skips the retry cooldown consistently -
    -- no cooldown is applied here on purpose, a resource restart isn't
    -- the player's fault).
    for player in pairs(pendingQuiz) do
        pendingQuiz[player] = nil
        if isElement(player) then
            triggerClientEvent(player, Events.LICENSE_EXAM_DIALOG_CLOSE, resourceRoot)
        end
    end

    for marker in pairs(categoryMarkers) do
        if isElement(marker) then
            destroyElement(marker)
        end
    end
    categoryMarkers = {}

    for blip in pairs(categoryBlips) do
        if isElement(blip) then
            destroyElement(blip)
        end
    end
    categoryBlips = {}

    if isTimer(examTickTimer) then
        killTimer(examTickTimer)
    end
end)
