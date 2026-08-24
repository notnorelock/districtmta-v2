addEvent(Events.LICENSE_EXAM_ENDED, true)
addEvent(Events.LICENSE_QUIZ_RESULT, true)
addEvent(Events.LICENSE_QUIZ_ANSWER, true)
addEvent(Events.LICENSE_EXAM_STARTED, true)
addEvent(Events.LICENSE_EXAM_DIALOG_OPEN, true)
addEvent(Events.LICENSE_EXAM_DIALOG_START, true)
addEvent(Events.LICENSE_EXAM_DIALOG_CLOSE, true)
addEvent(Events.LICENSE_EXAM_DIALOG_DISMISS, true)
addEvent(Events.LICENSE_EXAM_RETURN_FADE_IN, true)
addEvent(Events.LICENSE_EXAM_RETURN_FADE_OUT, true)
addEvent(Events.LICENSE_EXAM_OBJECTIVE_UPDATED, true)
addEvent(Events.LICENSE_QUIZ_QUESTIONS_RECEIVED, true)
addEvent(Events.LICENSE_EXAM_CHECKPOINT_CLEARED, true)
addEvent(Events.LICENSE_EXAM_CHECKPOINT_ACTIVATED, true)

local dialogOpen = false
local quizTickTimer = nil
local checkpointBlip = nil
local checkpointMarker = nil
local quizRemainingSeconds = 0

local function closeDialog()
    if not dialogOpen then
        return
    end
    dialogOpen = false

    stopQuizTicker()
    exports.core_ui:uiFocusBrowser(false)
    exports.core_ui:uiHideOverlay("licenseExam")
    toggleAllControls(true)
    showCursor(false)
end

local function stopQuizTicker()
    if isTimer(quizTickTimer) then
        killTimer(quizTickTimer)
    end
    quizTickTimer = nil
end

local function startQuizTicker()
    stopQuizTicker()
    quizTickTimer = setTimer(function()
        quizRemainingSeconds = math.max(0, quizRemainingSeconds - 1)
        exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_QUIZ_TICK, { remainingSeconds = quizRemainingSeconds })
    end, 1000, 0)
end

local function clearCheckpointVisual()
    if isElement(checkpointMarker) then
        destroyElement(checkpointMarker)
    end
    if isElement(checkpointBlip) then
        destroyElement(checkpointBlip)
    end
    checkpointMarker = nil
    checkpointBlip = nil
end

addEventHandler(Events.LICENSE_EXAM_ENDED, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_EXAM_ENDED, data)
end)

addEventHandler(Events.LICENSE_QUIZ_ANSWER, root, function(category, answerIndex)
    triggerServerEvent(Events.LICENSE_QUIZ_ANSWER, resourceRoot, category, answerIndex)
end)

addEventHandler(Events.LICENSE_QUIZ_RESULT, root, function(data)
    stopQuizTicker()
    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_QUIZ_RESULT, data)
end)

addEventHandler(Events.LICENSE_EXAM_STARTED, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_EXAM_STARTED, data)
end)

addEventHandler(Events.LICENSE_EXAM_DIALOG_OPEN, root, function(data)
    if not dialogOpen then
        dialogOpen = true
        exports.core_ui:uiFocusBrowser(true)
        toggleAllControls(false)
        showCursor(true)
    end

    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_EXAM_DIALOG_OPEN, data)
    exports.core_ui:uiShowOverlay("licenseExam")
end)

addEventHandler(Events.LICENSE_EXAM_DIALOG_CLOSE, root, closeDialog)

addEventHandler(Events.LICENSE_EXAM_DIALOG_START, root, function(category)
    triggerServerEvent(Events.LICENSE_EXAM_DIALOG_START, resourceRoot, category)
end)

addEventHandler(Events.LICENSE_EXAM_RETURN_FADE_OUT, root, function()
    fadeCamera(false, 0.5)
end)

addEventHandler(Events.LICENSE_EXAM_RETURN_FADE_IN, root, function()
    fadeCamera(true, 0.5)
end)

addEventHandler(Events.LICENSE_EXAM_DIALOG_DISMISS, root, closeDialog)
addEventHandler(Events.LICENSE_EXAM_CHECKPOINT_CLEARED, root, clearCheckpointVisual)

addEventHandler(Events.LICENSE_EXAM_CHECKPOINT_ACTIVATED, root, function(data)
    clearCheckpointVisual()
    if type(data) ~= "table" or type(data.position) ~= "table" then
        return
    end

    local pos = data.position
    local radius = data.radius or 4

    checkpointMarker = createMarker(pos.x, pos.y, pos.z - 0.9, "cylinder", radius, 30, 144, 255, 150)
    -- MTA blip icon 41 ("Race Checkpoint" style) - matches the reference
    -- script's own checkpoint marker convention.
    checkpointBlip = createBlip(pos.x, pos.y, pos.z, 41, 2, 255, 255, 255, 255)
end)

addEventHandler(Events.LICENSE_QUIZ_QUESTIONS_RECEIVED, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_QUIZ_QUESTIONS, data)
    if type(data) == "table" and type(data.remainingSeconds) == "number" then
        quizRemainingSeconds = data.remainingSeconds
        startQuizTicker()
    end
end)

addEventHandler(Events.LICENSE_EXAM_OBJECTIVE_UPDATED, root, function(data)
    exports.core_ui:uiPushEvent(Events.PUSH_LICENSE_EXAM_OBJECTIVE_UPDATED, data)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeDialog()
    clearCheckpointVisual()
end)
