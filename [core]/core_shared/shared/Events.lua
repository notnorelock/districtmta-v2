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

    -- Single generic channel every domain-specific CEF -> client Lua
    -- "fire and forget" notification goes through (MtaBridge.ts's
    -- notify(eventName, ...args)), instead of each resource's own client
    -- Lua registering an addEventHandler directly on window.mta.triggerEvent's
    -- target event name. window.mta.triggerEvent stringifies every
    -- argument on the way into Lua regardless of its real JS type
    -- (confirmed live: a JS number arrived here as a Lua STRING), so
    -- MtaTransport.ts's notify() JSON-encodes its whole args array and
    -- sends it as this one event's payload; core_ui/client/ui/Transport.lua's
    -- own handler (the only addEventHandler(Events.UI_NOTIFY, ...) in the
    -- project) decodes it back into real typed values and re-fires the
    -- ORIGINAL eventName via a plain triggerEvent(eventName, root, ...args)
    -- for whichever resource's own client Lua actually owns that event
    -- (gm_items/InventoryState.lua, gm_vehicles_interaction/
    -- VehicleInteractionState.lua, gm_interactions/WorldInteractionState.lua,
    -- ...) - those files read args normally now, with no per-resource
    -- JSON-decoding of their own.
    UI_NOTIFY = "ui.notify",

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
    PUSH_UI_OPEN = "ui.open",
    PUSH_UI_CLOSE = "ui.close",

    -- Server -> client: fired by ui_hud/server/NotificationBridge.lua
    -- (NOT triggered directly by callers - core's own NotificationService.
    -- send/.broadcast goes through exports.ui_hud:notificationBridgeShow/
    -- Broadcast rather than knowing this event at all, same as every other
    -- cross-resource entry point in this project - the resource that owns
    -- the behavior owns the transport). Rendered by ui_hud's own native
    -- dxDraw NotificationsComponent (NOT CEF - the toast stack this used
    -- to push into, packages/ui/src/features/notifications/, was
    -- removed). args: (type, title, message|nil), type is one of
    -- Enums.NotificationType. See ui_hud/client/Bootstrap.lua's handler
    -- for the type -> category mapping (NotificationsComponent's
    -- categories use "warn", not Enums.NotificationType's "warning").
    NOTIFICATION_SHOW = "notification:show",

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

    -- Server -> client (localPlayer only): confirms the local player's own
    -- talk-mode cycle request (see VOICE_CYCLE_MODE below) actually landed
    -- and names the new mode. Used to be a plain outputChatBox line
    -- (VoiceService.lua's own comment on why: cycling past the mode you
    -- want fires this several times in a row, too rapid for a toast
    -- queue/animation) - now relayed into the CEF HUD instead, see
    -- PUSH_VOICE_MODE_CHANGED below and HudBar.tsx's own transient
    -- tooltip-over-the-voice-icon.
    VOICE_MODE_CHANGED = "voice:modeChanged",
    -- Pushed into the CEF HUD once VOICE_MODE_CHANGED arrives - same
    -- "fires several times in a row while cycling" shape, the frontend's
    -- own timer just restarts on every push rather than queuing.
    PUSH_VOICE_MODE_CHANGED = "voice.modeChanged",

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

    -- Client -> server: sent once from gm_radio/client/RadioState.lua on
    -- onClientResourceStart, asking to be sent the fixed station list -
    -- request/response (rather than the server pushing it unprompted on
    -- join) so a mid-session gm_radio restart on either side still ends
    -- up with the client holding the list, not just a fresh connection.
    RADIO_REQUEST_STATIONS = "radio:requestStations",

    -- Server -> requesting client only: response to RADIO_REQUEST_STATIONS,
    -- the full fixed station list in order. RadioState.lua stores it and
    -- forwards it into the CEF HUD via PUSH_RADIO_STATIONS.
    RADIO_STATIONS_RECEIVED = "radio:stationsReceived",

    -- Pushed into the CEF HUD once RADIO_STATIONS_RECEIVED arrives - the
    -- full fixed station list in order, so the frontend can show the
    -- upcoming station's name next to the skip-forward/back glyphs
    -- instead of just the currently-playing one (see RadioCard.tsx).
    PUSH_RADIO_STATIONS = "radio.stations",

    -- Server -> localPlayer only: fired when gm_blackout puts a player
    -- into blackout (near-fatal damage intercepted before it would have
    -- killed them, or a revive-in-place after an already-fatal hit that
    -- bypassed onPlayerDamage entirely - see BlackoutService.lua's own
    -- comment on why both paths exist) and again when it ends (early, via
    -- the countdown reaching zero, or an admin/future medic action).
    -- `until_` is the same absolute os.time() end value mirrored onto
    -- ElementData.Player.BLACKOUT_UNTIL, nil on end.
    BLACKOUT_STARTED = "blackout:started",
    BLACKOUT_ENDED = "blackout:ended",

    -- Pushed into the CEF HUD (gm_blackout/client/BlackoutState.lua) on
    -- every UI-relevant tick while blacked out - see BlackoutOverlay.tsx.
    -- secondsRemaining is nil once null/not blacked out (hides the overlay).
    PUSH_BLACKOUT_UPDATED = "blackout.updated",

    -- Client -> server: player pressed E while blacked out, requesting to
    -- get back up on their own instead of waiting for a future medic
    -- system. Server is authoritative - only actually ends blackout if
    -- the countdown has genuinely reached zero (BlackoutState.lua only
    -- binds E once its own local countdown hits zero, but the server
    -- re-checks BlackoutService.secondsRemaining independently rather
    -- than trusting client timing at all).
    BLACKOUT_SELF_REVIVE = "blackout:selfRevive",

    -- Client -> server: gm_scoreboard/client/ScoreboardState.lua asking to
    -- be sent the current player list. Request/response (like
    -- RADIO_REQUEST_STATIONS) rather than an unprompted server push, fired
    -- once on resource start and again on every TAB-down - the list can go
    -- stale between holds (players join/quit/change status), so each hold
    -- re-requests rather than relying on a a stream of periodic pushes.
    SCOREBOARD_REQUEST_PLAYERS = "scoreboard:requestPlayers",

    -- Server -> requesting client only: response to SCOREBOARD_REQUEST_PLAYERS,
    -- the full connected-player list as plain data (see ScoreboardService.lua's
    -- toEntry for the exact shape). ScoreboardState.lua forwards it into the
    -- CEF overlay via PUSH_SCOREBOARD_PLAYERS.
    SCOREBOARD_PLAYERS_RECEIVED = "scoreboard:playersReceived",

    -- Pushed into the CEF overlay once SCOREBOARD_PLAYERS_RECEIVED arrives.
    PUSH_SCOREBOARD_PLAYERS = "scoreboard.players",

    -- Client -> server: gm_worldmap/client/WorldMapState.lua asking for a
    -- fresh snapshot of everything the F11 world map shows - same
    -- request/response-while-open + refresh-timer shape as
    -- SCOREBOARD_REQUEST_PLAYERS, for the same reason (player positions
    -- go stale between refreshes, and there's no point broadcasting to
    -- players who don't have the map open).
    WORLDMAP_REQUEST_DATA = "worldmap:requestData",

    -- Server -> requesting client only: response to WORLDMAP_REQUEST_DATA,
    -- { players, stores } - see WorldMapService.lua's toPlayerEntry/
    -- toStoreEntry for the exact shape of each. WorldMapState.lua forwards
    -- it into the CEF overlay via PUSH_WORLDMAP_DATA.
    WORLDMAP_DATA_RECEIVED = "worldmap:dataReceived",

    -- Pushed into the CEF overlay once WORLDMAP_DATA_RECEIVED arrives.
    PUSH_WORLDMAP_DATA = "worldmap.data",

    -- Server-to-server bridge between gm_vehicles (owns the handler
    -- closure/callback) and core (owns VehicleRepository/the database) -
    -- the same requestId-correlated request/response shape FetchBridge
    -- uses across the core/core_ui boundary (see Architecture.md's "The
    -- one hard rule for extending the project": a callback can never
    -- cross a resource boundary, only plain data can). gm_vehicles's
    -- VehicleBridge.lua triggers VEHICLE_REPOSITORY_REQUEST with
    -- { requestId, method, args }; core's VehicleService.lua runs the
    -- matching VehicleRepository method and triggers
    -- VEHICLE_REPOSITORY_RESPONSE back with { requestId, ok, result }.
    -- Both fire via plain triggerEvent (not triggerServerEvent/
    -- triggerClientEvent - this never touches a player/client, it's
    -- server-side Lua talking to server-side Lua in a different resource).
    VEHICLE_REPOSITORY_REQUEST = "core:vehicleRepositoryRequest",
    VEHICLE_REPOSITORY_RESPONSE = "vehicles:vehicleRepositoryResponse",

    -- Server-to-server bridge between gm_groups (owns the handler
    -- closure/callback) and core (owns GroupRepository/GroupRankRepository/
    -- GroupMemberRepository/the database) - same requestId-correlated
    -- request/response shape as VEHICLE_REPOSITORY_REQUEST/_RESPONSE above,
    -- covering all three group repositories through one whitelist (see
    -- core/server/GroupService.lua's own METHODS table), same as that pair
    -- already covers both VehicleRepository and VehicleStoreRepository.
    -- Both fire via plain triggerEvent (server-side Lua talking to
    -- server-side Lua in a different resource, no player/client involved).
    GROUP_REPOSITORY_REQUEST = "core:groupRepositoryRequest",
    GROUP_REPOSITORY_RESPONSE = "groups:groupRepositoryResponse",

    -- Server -> localPlayer: fired by gm_groups/server/GroupDutyService.lua's
    -- enterDuty/exitDuty when the player walks into/out of their group's
    -- duty marker.
    GROUP_DUTY_STARTED = "groups:dutyStarted",
    GROUP_DUTY_ENDED = "groups:dutyEnded",
    -- Server -> localPlayer: periodic duty tick sync (see
    -- GroupDutyService.lua's own module comment on the tick interval),
    -- carries { totalSeconds } - the CEF duty indicator always shows a
    -- server-confirmed running total, not a purely client-side guess.
    GROUP_DUTY_SYNC = "groups:dutySync",

    -- Pushed into the CEF duty indicator once GROUP_DUTY_STARTED/_ENDED/_SYNC arrive.
    PUSH_GROUP_DUTY_STARTED = "groups.dutyStarted",
    PUSH_GROUP_DUTY_ENDED = "groups.dutyEnded",
    PUSH_GROUP_DUTY_SYNC = "groups.dutySync",

    -- Client -> server: player opened the group management panel, wants a
    -- fresh snapshot of every group they belong to (ranks + own
    -- memberships) - request/response (like INVENTORY_REQUEST_ITEMS)
    -- rather than an unprompted push, re-requested on every open.
    GROUP_REQUEST_MINE = "groups:requestMine",

    -- Server -> requesting client only: response to GROUP_REQUEST_MINE -
    -- see GroupEndpoints.lua's own toMinePayload for the exact shape.
    -- GroupPanelState.lua forwards it into the CEF panel via PUSH_GROUP_MINE.
    GROUP_MINE_RECEIVED = "groups:mineReceived",

    -- Pushed into the CEF panel once GROUP_MINE_RECEIVED arrives, and
    -- again any time the server changes something about the player's own
    -- group membership/ranks (rank edited, member assigned/kicked) so the
    -- panel stays live while open - same "re-push after every mutation"
    -- shape PUSH_INVENTORY_ITEMS already uses.
    PUSH_GROUP_MINE = "groups.mine",

    -- Client -> server: player selected one of their groups' "Members" tab
    -- in the panel, wants the full roster - { groupId }. Server only
    -- answers if the requester is actually a member of that group.
    GROUP_REQUEST_MEMBERS = "groups:requestMembers",
    -- Server -> requesting client only: response to GROUP_REQUEST_MEMBERS,
    -- { groupId, members }. GroupPanelState.lua forwards it via PUSH_GROUP_MEMBERS.
    GROUP_MEMBERS_RECEIVED = "groups:membersReceived",
    -- Pushed into the CEF panel once GROUP_MEMBERS_RECEIVED arrives, and
    -- again after any member-affecting mutation (rank assign/kick) for
    -- whichever group is currently open in the Members tab.
    PUSH_GROUP_MEMBERS = "groups.members",

    -- Client -> server: leader/manage_ranks member creating a new rank on
    -- one of their groups - { groupId, name, skin, hourlyReward,
    -- permissions, sortOrder }. Server re-derives the requester's own
    -- permission from their group_members row, never trusts the panel.
    GROUP_CREATE_RANK = "groups:createRank",
    -- Client -> server: { rankId, name, skin, hourlyReward, permissions, sortOrder }.
    GROUP_UPDATE_RANK = "groups:updateRank",
    -- Client -> server: { rankId } - rejected server-side if any member
    -- currently holds it or it's the group's only rank.
    GROUP_DELETE_RANK = "groups:deleteRank",
    -- Client -> server: { memberId, rankId } - requester's own rank must
    -- be more senior (lower sort_order) than both the target's current
    -- and new rank.
    GROUP_ASSIGN_MEMBER_RANK = "groups:assignMemberRank",
    -- Client -> server: { memberId } - cannot target the group's own leader.
    GROUP_KICK_MEMBER = "groups:kickMember",
    -- Client -> server: { groupId } - self-service leave; the leader must
    -- transfer leadership first (no UI for that in v1, command-only via an
    -- admin if ever needed).
    GROUP_LEAVE = "groups:leave",

    -- Client -> server: { groupId } - manage_members member opening the
    -- "Add member" picker wants the list of online players not already in
    -- this group. Server re-derives the requester's own permission.
    GROUP_REQUEST_INVITABLE_PLAYERS = "groups:requestInvitablePlayers",
    -- Server -> requesting client only: response, { groupId, players:
    -- [{ accountId, name }] }.
    GROUP_INVITABLE_PLAYERS_RECEIVED = "groups:invitablePlayersReceived",
    PUSH_GROUP_INVITABLE_PLAYERS = "groups.invitablePlayers",

    -- Client -> server: manage_members member picked a player from the
    -- invite picker - { groupId, accountId }. Rejected if already a
    -- member, already has a pending invite, or the target isn't online.
    GROUP_INVITE_PLAYER = "groups:invitePlayer",

    -- Server -> the INVITED player only, fired the moment an invite is
    -- created - { inviteId, groupId, groupName, groupType, invitedByName }.
    -- GroupPanelState.lua forwards it into a small standalone CEF prompt
    -- (own "groupInvite" overlay, NOT gated behind the main group panel
    -- being open) via PUSH_GROUP_INVITE_RECEIVED.
    GROUP_INVITE_RECEIVED = "groups:inviteReceived",
    PUSH_GROUP_INVITE_RECEIVED = "groups.inviteReceived",

    -- Client -> server: invitee requests their own current pending
    -- invites (panel/prompt bootstrap on login/resource start) - no payload.
    GROUP_REQUEST_INVITES = "groups:requestInvites",
    -- Server -> requesting client only: response, an array of the same
    -- shape GROUP_INVITE_RECEIVED pushes per-invite.
    GROUP_INVITES_RECEIVED = "groups:invitesReceived",
    PUSH_GROUP_INVITES = "groups.invites",

    -- Client -> server: { inviteId } - invitee accepting; server
    -- re-verifies the invite still belongs to the requester's own account
    -- before creating the group_members row (rank_id = nil).
    GROUP_ACCEPT_INVITE = "groups:acceptInvite",
    -- Client -> server: { inviteId } - invitee declining (or the
    -- inviter/a manage_members member revoking - same delete, no
    -- distinction needed since either just removes the pending row).
    GROUP_DECLINE_INVITE = "groups:declineInvite",

    -- Client -> server: driver requested toggling one vehicle system
    -- (engine/lights/lock) from the radial interaction menu (see
    -- gm_vehicles/client/VehicleInteractionState.lua). `action` is one of
    -- "engine"/"lights"/"lock" - server re-validates the requester is
    -- actually this vehicle's driver before touching anything (never
    -- trusts the client's own menu-open gate).
    VEHICLE_INTERACTION_TOGGLE = "vehicles:interactionToggle",

    -- Client -> server: fired once when the radial menu first opens, to
    -- learn the vehicle's current engine/lights/lock state without
    -- toggling anything - see VEHICLE_INTERACTION_TOGGLE's own handler,
    -- kept as a separate event rather than a bare-string suffix hack so
    -- every event name in this registry stays a real, grep-able constant.
    VEHICLE_INTERACTION_QUERY = "vehicles:interactionQuery",

    -- Server -> every occupant of the vehicle (not just the driver who
    -- requested it) once a toggle actually happened - { action, state }
    -- lets a passenger's own HUD (future work) or just the vehicle's real
    -- synced state stay consistent without polling. Also sent to the
    -- driver alone right when the interaction menu opens, to seed its
    -- initial state. Re-used as BOTH the client<->client Lua event name
    -- (VehicleInteractionState.lua re-triggers it locally, source-checked
    -- against localPlayer) AND the CEF push event name it forwards into -
    -- same string serves both hops, no separate constant needed since
    -- neither hop's payload shape differs.
    PUSH_VEHICLE_INTERACTION_STATE = "vehicles.interactionState",

    -- Client Lua -> CEF only (uiPushEvent, never triggerEvent) - scroll
    -- wheel direction while the radial menu is open, forwarded so the
    -- frontend can move its own current-selection without Lua needing to
    -- track which of the (client-side-only, cosmetic) menu slices is
    -- highlighted. true = wheel up, false = wheel down.
    PUSH_VEHICLE_INTERACTION_SCROLL = "vehicles.interactionScroll",

    -- Client Lua -> CEF only (uiPushEvent) - space bar pressed while the
    -- radial menu is open, telling the frontend to activate whichever
    -- option it currently has selected.
    PUSH_VEHICLE_INTERACTION_ACTIVATE = "vehicles.interactionActivate",

    -- CEF -> client Lua (via MtaBridge.notify, not uiPushEvent - this is
    -- the browser telling Lua something, the reverse direction of the two
    -- push events above) - the frontend's own currently-selected option
    -- was activated (space bar), naming which action ("engine"/"lights"/
    -- "lock") to actually request from the server. See
    -- VehicleInteractionState.lua's addEventHandler for this.
    VEHICLE_INTERACTION_ACTIVATED = "vehicles:interactionActivated",

    -- World interaction (gm_interactions) - hold E near a player/vehicle/
    -- object to see its available interactions, mirrors the vehicle
    -- interaction ring's own client-owns-the-menu-UI split: WorldState.lua
    -- (client) decides which element is targeted and asks the server for
    -- ITS interaction list (never trusts a client-built list), the
    -- frontend only renders + tracks the scroll/keyboard selection.

    -- Client -> server: E pressed near `element` (closest-to-screen-center
    -- candidate the client found, see WorldInteractionState.lua) - asking
    -- which interactions (if any) are available on it right now. Server
    -- re-derives the list itself (role/rank/condition checks all run
    -- server-side, see InteractionRegistry.lua) rather than trusting
    -- anything the client claims about itself.
    INTERACTION_REQUEST_LIST = "interactions:requestList",

    -- Server -> requesting client only: response to INTERACTION_REQUEST_LIST -
    -- { items: { key, label, icon }[] }, empty/absent items means "nothing
    -- to show here", not an error - see InteractionRegistry.lua's toEntries.
    INTERACTION_LIST_RECEIVED = "interactions:listReceived",

    -- Pushed into the CEF overlay once INTERACTION_LIST_RECEIVED arrives,
    -- and again (empty) when the target is lost/E released - see
    -- WorldInteractionOverlay.tsx.
    PUSH_INTERACTION_LIST = "interactions.list",

    -- Client Lua -> CEF only (uiPushEvent) - the target element's current
    -- screen position, refreshed every render frame while E is held so the
    -- pointer diamond/line tracks it - see WorldInteractionState.lua's own
    -- module comment on why this is a separate high-frequency push from
    -- the low-frequency interaction list above.
    PUSH_INTERACTION_TARGET = "interactions.target",

    -- Client Lua -> CEF only (uiPushEvent) - scroll wheel / arrow key
    -- direction while the overlay is open, same pattern as
    -- PUSH_VEHICLE_INTERACTION_SCROLL.
    PUSH_INTERACTION_NAVIGATE = "interactions.navigate",

    -- Client Lua -> CEF only (uiPushEvent) - space bar pressed while a
    -- target is active, telling the frontend to activate whichever item
    -- it currently has selected. Separate from PUSH_INTERACTION_NAVIGATE
    -- (which only moves the selection) - same split
    -- PUSH_VEHICLE_INTERACTION_SCROLL/PUSH_VEHICLE_INTERACTION_ACTIVATE use.
    PUSH_INTERACTION_ACTIVATE = "interactions.activate",

    -- CEF -> client Lua (via MtaBridge.notify) - the frontend's own
    -- currently-selected item was activated (space/enter/click), naming
    -- which item `key` to actually request from the server.
    INTERACTION_ACTIVATED = "interactions:activated",

    -- Client -> server: relays INTERACTION_ACTIVATED's key together with
    -- the target element that was current when the overlay opened - server
    -- re-validates both the element is still valid/in range AND the
    -- interaction is still allowed before running its handler (never
    -- trusts the client's own "it's allowed" belief from the list it was
    -- shown a moment earlier).
    INTERACTION_CALL = "interactions:call",

    -- Server-to-server bridge between gm_items (owns the handler closure/
    -- callback) and core (owns ItemRepository/the database) - the exact
    -- same requestId-correlated request/response shape
    -- VEHICLE_REPOSITORY_REQUEST/_RESPONSE uses (see its own comment and
    -- docs/Architecture.md's "the one hard rule"). gm_items/server/
    -- ItemBridge.lua triggers ITEM_REPOSITORY_REQUEST with
    -- { requestId, method, args }; core/server/ItemService.lua
    -- runs the matching ItemRepository method and triggers
    -- ITEM_REPOSITORY_RESPONSE back with { requestId, ok, result }. Both
    -- fire via plain triggerEvent, not triggerServerEvent/triggerClientEvent.
    ITEM_REPOSITORY_REQUEST = "core:itemRepositoryRequest",
    ITEM_REPOSITORY_RESPONSE = "items:itemRepositoryResponse",

    -- Client -> server: player pressed I, wants a fresh snapshot of their
    -- own inventory - request/response (like SCOREBOARD_REQUEST_PLAYERS)
    -- rather than an unprompted push, re-requested on every open so
    -- amount/favorite changes since the last open are never stale.
    INVENTORY_REQUEST_ITEMS = "inventory:requestItems",

    -- Server -> requesting client only: response to INVENTORY_REQUEST_ITEMS,
    -- the player's full item list as plain data - see ItemService.lua's
    -- toEntry for the exact shape. InventoryState.lua forwards it into the
    -- CEF overlay via PUSH_INVENTORY_ITEMS.
    INVENTORY_ITEMS_RECEIVED = "inventory:itemsReceived",

    -- Pushed into the CEF overlay once INVENTORY_ITEMS_RECEIVED arrives,
    -- and again any time the server changes the player's items on its own
    -- (picked up/used/dropped/received) so the panel stays live while open.
    PUSH_INVENTORY_ITEMS = "inventory.items",

    -- Client -> server: player chose "Użyj" on an item (its database row
    -- id) from the inventory panel. Server re-validates ownership and the
    -- item's own scheme before running its effect - never trusts the
    -- panel's own belief that using it is valid.
    INVENTORY_USE_ITEM = "inventory:useItem",

    -- Client -> server: player chose "Wyrzuć" on an item - drops it as a
    -- world object at the player's own current position (server-derived,
    -- never a client-supplied position).
    INVENTORY_DROP_ITEM = "inventory:dropItem",

    -- Client -> server: player toggled the "favorite" star on an item -
    -- purely a per-account display preference, no gameplay effect.
    INVENTORY_TOGGLE_FAVORITE = "inventory:toggleFavorite",

    -- World item pickup, via gm_interactions' own generic "object:
    -- itemPickup" InteractionRegistry entry (registered in
    -- gm_interactions/server/InteractionRegistry.lua itself, not gm_items -
    -- a handler function can't cross the resource boundary, so gm_items
    -- can't register its own entry there; see that file's own comment on
    -- this entry) rather than a bespoke detection system, same reasoning
    -- gm_interactions' own module comment gives for reusing it. Fired via
    -- plain triggerEvent (server-to-server, gm_interactions -> gm_items),
    -- not triggerServerEvent/triggerClientEvent - `player` is passed
    -- explicitly since this never touches a client/browser.
    -- gm_items/server/ItemPickupHandler.lua re-validates range/ownerless-
    -- ness itself (InteractionService.lua already re-validated range
    -- generically before calling the handler; this only carries the
    -- specific item row id through to gm_items).
    ITEM_PICKUP = "items:pickup",

    -- Client -> server: a nametag just came into view (onClientElementStreamIn)
    -- and needs role/duty/level data no ElementData key exposes client-side
    -- (role/duty are server-only concepts - see PlayerService.lua/
    -- Permissions.lua, both server modules with no client export chain).
    -- gm_nametags/server/NametagService.lua responds for exactly that one
    -- player, not a full roster push - a streamed-in nametag only needs
    -- data for the player that just appeared.
    NAMETAG_REQUEST_DATA = "nametags:requestData",
    -- Server -> client: response to NAMETAG_REQUEST_DATA, `player` echoed
    -- back so the client can match it to the right streamablePlayers entry
    -- (requests can race - a player might stream out before the response
    -- for their stream-in arrives).
    NAMETAG_DATA_RECEIVED = "nametags:dataReceived",

    -- Vehicle storage lots (gm_vehicles/server/VehicleStorageService.lua) -
    -- walking into a lot's enter marker opens the CEF panel listing every
    -- vehicle THIS account owns that's currently sitting in THIS lot
    -- (store_id = that lot's id). Server -> client, `player` implicit
    -- (targeted triggerClientEvent, not broadcast) - fired the moment the
    -- marker is entered, no client -> server request needed first (unlike
    -- inventory/scoreboard's own request/response pattern) since the
    -- server already knows which lot and which account without the client
    -- asking.
    VEHICLE_STORAGE_OPEN = "vehicles:storageOpen",
    -- Client -> server: walked out of the enter marker - closes the panel
    -- client-side (VehicleStorageState.lua) without needing a round trip.
    VEHICLE_STORAGE_CLOSE = "vehicles:storageClose",

    -- Server -> requesting client only: the lot's vehicle list, keyed to
    -- VEHICLE_STORAGE_OPEN's own storeId - see VehicleStorageService.lua's
    -- toEntry for the exact shape. VehicleStorageState.lua forwards it
    -- into the CEF panel via PUSH_VEHICLE_STORAGE_ITEMS.
    VEHICLE_STORAGE_ITEMS_RECEIVED = "vehicles:storageItemsReceived",
    -- Pushed into the CEF panel once VEHICLE_STORAGE_ITEMS_RECEIVED arrives.
    PUSH_VEHICLE_STORAGE_ITEMS = "vehicles.storageItems",

    -- Client -> server: player picked a vehicle (its database row id) from
    -- the storage panel to retrieve. Server re-validates ownership OR
    -- vehicle-key possession (borrowing someone else's vehicle - see
    -- VehicleStorageService.lua's own playerHasKeyTo) and that the
    -- vehicle is genuinely still in this lot before spawning it - never
    -- trusts the panel's own belief that retrieving it is valid.
    VEHICLE_STORAGE_RETRIEVE = "vehicles:storageRetrieve",

    -- Storing a vehicle has NO event of its own - driving onto a lot's
    -- store_position colshape stores it automatically, entirely server-
    -- side (see gm_vehicles/server/VehicleStorageService.lua's
    -- onStoreZoneHit/tryStoreVehicle) - no client involvement at all.

    -- Server-to-server, core -> gm_vehicles (fire-and-forget, no response -
    -- unlike VEHICLE_REPOSITORY_REQUEST/_RESPONSE, nothing here needs a
    -- result back). core/server/commands/AdminCommands.lua's own
    -- /createstore, /addstorespawn, /movestore, /removestore all trigger
    -- this once their own database write finishes, so
    -- VehicleStorageService.lua's own VehicleStorageService.reload() can
    -- destroy its current markers and re-fetch vehicle_stores from
    -- scratch - without this, an admin would have to manually restart
    -- gm_vehicles after every single storage-lot edit for it to take
    -- effect (see VehicleStorageService.lua's own module comment on why
    -- markers aren't otherwise live).
    VEHICLE_STORE_RELOAD = "core:vehicleStoreReload",
}
