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

    -- Server -> client: fired instead of AUTH_BEGIN_AUTHENTICATION/
    -- SPAWN_SELECT_OPEN when LOADING_READY fires for a player who is
    -- already logged in AND already spawned - i.e. a resource restart
    -- mid-session (core_ui/core_loading/core_auth restarted, CEF
    -- remounted from scratch) rather than a fresh join. Neither auth nor
    -- spawn-select ever gets a ui.open push in this case, since there's
    -- genuinely no window to open - without this, uiStore's
    -- hasOpenedAnyWindow stays false forever and the frontend is stuck
    -- showing ResourceCheckScreen despite the player already being in
    -- the world. See AuthUiClient.lua/ui.store.ts.
    AUTH_ALREADY_IN_WORLD = "auth:alreadyInWorld",

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

    -- Pushed by AuthUiClient.lua on Events.AUTH_ALREADY_IN_WORLD - tells
    -- the frontend directly "there is no window to open, stop showing the
    -- loading screen" without having to fake a ui.open/ui.close pair for
    -- a window that never actually opens. See ui.store.ts's
    -- hasOpenedAnyWindow.
    PUSH_UI_ALREADY_IN_WORLD = "ui.alreadyInWorld",

    -- Overlays (UI.showOverlay/hideOverlay in BrowserManager.lua) are a
    -- separate registry from openWindows - never affect showCursor/
    -- guiSetInputEnabled, and (unlike windows) are never toggled by the
    -- browser itself, only by Lua script code. HUD is the first user.
    PUSH_OVERLAY_SHOW = "overlay.show",
    PUSH_OVERLAY_HIDE = "overlay.hide",

    -- ui_hud/client's own local read of localPlayer's health, pushed into
    -- the browser directly - never touches the server (see
    -- ui_hud/client/HudState.lua). hunger/thirst/voice are placeholders,
    -- no server-side system backs them yet.
    PUSH_HUD_UPDATED = "hud.updated",

    -- gm_voice/client's own local list of nearby speakers (name + voice
    -- mode), pushed into the browser directly on talking-list change -
    -- never touches the server (see gm_voice/client/VoiceState.lua).
    -- Separate from PUSH_HUD_UPDATED's voiceActive (which is only "is the
    -- LOCAL player talking") - this is "who ELSE nearby is talking right now".
    PUSH_VOICE_NEARBY_UPDATED = "voice.nearbyUpdated",

    -- Client -> server: player pressed the cycle-voice-mode key (B).
    -- Server is authoritative over the resulting mode (drives broadcast
    -- distance in VoiceService.lua) - the client only requests a cycle,
    -- it never sets ElementData.Player.VOICE_MODE itself.
    VOICE_CYCLE_MODE = "voice:cycleMode",

    -- Client -> server: driver scrolled/pressed R to change the vehicle
    -- radio station. `next` boolean (true = forward, false = back).
    -- Server is authoritative (validates the driver seat + station list),
    -- see gm_radio/server/RadioService.lua.
    RADIO_CHANGE_STATION = "radio:changeStation",

    -- Server -> every occupant of a vehicle whose station changed -
    -- station is nil for "off". Client (gm_radio/client/RadioState.lua)
    -- both plays the stream AND pushes PUSH_RADIO_STATION_CHANGED into
    -- the CEF HUD from this same handler.
    RADIO_STATION_CHANGED = "radio:stationChanged",

    -- Pushed into the CEF HUD (gm_radio/client/RadioState.lua) whenever
    -- the local player's vehicle radio station changes, and hidden again
    -- on RADIO_CARD_HIDE (a few seconds later, or on vehicle exit).
    -- station is nil for "off" (hides the card immediately instead).
    PUSH_RADIO_STATION_CHANGED = "radio.stationChanged",
}
