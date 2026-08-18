-- Tracks this client's own resource-download progress and pushes it into
-- CEF - see docs/Architecture.md's loading-screen section.
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
    pushProgress({
        visible = isVisible,
        downloadedSize = 0,
        totalSize = 0,
    })
end)
