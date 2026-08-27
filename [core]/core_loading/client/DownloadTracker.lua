-- Tracks this client's own resource-download progress and pushes it into
-- CEF - see docs/Architecture.md's loading-screen section.

-- Guards against sending Events.DOWNLOAD_FINISHED more than once -
-- onClientTransferBoxVisibilityChange(false) is MTA's own native event
-- (not something this file triggers itself, so there's no risk of a
-- feedback loop from it), but MTA can still show/hide the transfer box
-- more than once in a session (e.g. downloading additional resources
-- mid-session) - only the FIRST "downloads finished" matters for
-- LoadingGate.lua's purposes, so later ones are no-ops here.
local downloadFinishedSent = false

local function pushProgress(data)
    local ok, err = pcall(function()
        exports.core_ui:uiPushEvent("loading.progress", data)
    end)
    if not ok then
        outputDebugString("DownloadTracker: uiPushEvent failed - " .. tostring(err), 2)
    end
end

addEventHandler("onClientTransferBoxProgressChange", root, function(downloadedSize, totalSize)
    pushProgress({
        visible = true,
        downloadedSize = downloadedSize,
        totalSize = totalSize,
    })
end)

addEventHandler("onClientTransferBoxVisibilityChange", root, function(isVisible)
    outputDebugString("[DEBUG][core_loading] onClientTransferBoxVisibilityChange: " .. tostring(isVisible))

    pushProgress({
        visible = isVisible,
        downloadedSize = 0,
        totalSize = 0,
    })

    if isVisible == false and not downloadFinishedSent then
        downloadFinishedSent = true
        triggerServerEvent(Events.DOWNLOAD_FINISHED, localPlayer)
    end
end)
