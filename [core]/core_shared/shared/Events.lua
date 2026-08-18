-- Canonical event name registry shared between server and client Lua.
-- Every custom MTA event fired across resource boundaries must be
-- declared here instead of typed as a raw string literal at the call
-- site. See docs/Architecture.md for what each event chain does.

Events = {
    -- Fired once Schema.migrate() finishes - NOT the same moment as
    -- core's own onResourceStart. Anything querying the database from a
    -- "just started" hook must wait for this instead.
    DATABASE_READY = "core:databaseReady",

    PLAYER_ACCOUNT_RESOLVED = "core:player.accountResolved",
    PLAYER_ACCOUNT_CLEARED = "core:player.accountCleared",
    PLAYER_PREMIUM_EXPIRED = "core:player.premiumExpired",

    -- FetchBridge transport (client <-> server)
    UI_FETCH_REQUEST = "ui:fetchData",
    UI_FETCH_RESPONSE = "ui:fetchDataResponse",

    -- FetchBridge push channel (server -> client -> browser, not RPC responses)
    UI_PUSH_EVENT = "ui:event",

    -- Browser <-> client Lua (not networked, browser events only)
    BROWSER_READY = "ui.ready",

    -- Local-only "remember me" credential persistence (browser <-> client
    -- Lua only - never touches the server)
    CREDENTIALS_SAVE = "credentials.save",
    CREDENTIALS_LOAD = "credentials.load",
    CREDENTIALS_CLEAR = "credentials.clear",

    -- AUTH_SUCCESS_AUTHENTICATION only means "close the auth window" -
    -- not "player is in the game world" (that waits on spawn selection).
    AUTH_BEGIN_AUTHENTICATION = "auth:beginAuthentication",
    AUTH_SUCCESS_AUTHENTICATION = "auth:successAuthentication",

    SPAWN_SELECT_OPEN = "spawn:selectOpen",
    SPAWN_SELECT_CLOSE = "spawn:selectClose",

    -- Native dxGUI/dxDraw admin windows, NOT CEF - unrelated to PUSH_UI_OPEN/_CLOSE.
    ADMIN_PANEL_TOGGLE = "admin:panelToggle",
    REPORTS_OVERLAY_TOGGLE = "admin:reportsOverlayToggle",

    -- dxGUI admin panel request/response pairs (plain triggerServerEvent/
    -- triggerClientEvent, no CEF/FetchBridge involved).
    ADMIN_REQUEST_PLAYER_LIST = "admin:requestPlayerList",
    ADMIN_PLAYER_LIST = "admin:playerList",
    ADMIN_REQUEST_REPORT_LIST = "admin:requestReportList",
    ADMIN_REPORT_LIST = "admin:reportList",
    ADMIN_RESOLVE_REPORT = "admin:resolveReport",
    ADMIN_ISSUE_PENALTY = "admin:issuePenalty",

    ADMIN_REQUEST_STATS = "admin:requestStats",
    ADMIN_STATS = "admin:stats",

    -- Self-targeted; { viewStats: boolean }, VIEW_STATS is RCON+/BOARD-only.
    ADMIN_PERMISSIONS = "admin:permissions",

    REPORT_CREATED = "admin:reportCreated",
    ADMIN_REPORT_CREATED_NOTICE = "admin:reportCreatedNotice",
    ADMIN_DUTY_CHANGED = "admin:dutyChanged",

    -- Client -> server, sent on resource start so a client that
    -- (re)starts after duty was already toggled learns the current state.
    ADMIN_REQUEST_DUTY_STATUS = "admin:requestDutyStatus",

    -- Fired once BOTH core_bootstrap's chain and this player's CEF are ready.
    LOADING_READY = "loading:ready",

    -- Push event names delivered over UI_PUSH_EVENT (CEF-bound only)
    PUSH_ACCOUNT_UPDATED = "account.updated",
    PUSH_ACCOUNT_RESOLVED = "account.resolved",
    PUSH_NOTIFICATION_CREATED = "notification.created",
    PUSH_UI_OPEN = "ui.open",
    PUSH_UI_CLOSE = "ui.close",
}
