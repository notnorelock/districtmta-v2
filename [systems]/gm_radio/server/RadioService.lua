-- Vehicle radio: a fixed station list (no per-account saved stations for
-- now - see this resource's own README-style module comment in meta.xml),
-- driver-only control, broadcast to every occupant on change. Station
-- state lives on the vehicle itself (ElementData.Vehicle.RADIO_STATION),
-- not per-player, so every occupant (including one who enters mid-ride)
-- sees/hears the same station.
RadioService = RadioService or {}

-- Direct stream URLs only - no YouTube/third-party conversion service
-- (the old version of this used an external ytdl.codeity.pl proxy, which
-- isn't a service this project owns or can rely on staying up).
local STATIONS = {
    { name = "RMF FM", url = "http://www.rmfon.pl/n/rmffm.pls" },
    { name = "Eska", url = "http://acdn.smcloud.net/t046-1.mp3.pls" },
    { name = "Eska Rock", url = "http://acdn.smcloud.net/t041-1.mp3.pls" },
    { name = "Radio Zet", url = "http://zet-net-01.cdn.eurozet.pl:8400/listen.pls" },
    { name = "RMF MAXX", url = "http://www.rmfon.pl/n/rmfmaxxx.pls" },
    { name = "Antyradio", url = "http://ant-waw-01.cdn.eurozet.pl:8602/listen.pls" },
    { name = "REYFM - Charts", url = "https://listen.reyfm.de/reyfm-charts/" },
    { name = "REYFM - Dance", url = "https://listen.reyfm.de/reyfm-dance/" },
    { name = "REYFM - Deutschrap", url = "https://listen.reyfm.de/reyfm-deutschrap/" },
    { name = "REYFM - Hits", url = "https://listen.reyfm.de/reyfm-hits/" },
    { name = "REYFM - Piano House", url = "https://listen.reyfm.de/reyfm-piano_house/" },
    { name = "REYFM - Hip-Hop", url = "https://listen.reyfm.de/reyfm-hip-hop/" },
    { name = "REYFM - Hits2K", url = "https://listen.reyfm.de/reyfm-hits2k/" },
    { name = "REYFM - Summer", url = "https://listen.reyfm.de/reyfm-summer/" },
    { name = "REYFM - Original", url = "https://listen.reyfm.de/reyfm-original/" },
    { name = "REYFM - Deutschrap Gold", url = "https://listen.reyfm.de/reyfm-deutschrap_gold/" },
    { name = "REYFM - Hip-Hop Gold", url = "https://listen.reyfm.de/reyfm-hip-hop_gold/" },
    { name = "REYFM - Lo-Fi", url = "https://listen.reyfm.de/reyfm-lofi/" },
    { name = "REYFM - Chill", url = "https://listen.reyfm.de/reyfm-chill/" },
    { name = "REYFM - Gaming", url = "https://listen.reyfm.de/reyfm-gaming/" },
    { name = "REYFM - XMAS", url = "https://listen.reyfm.de/reyfm-party_unlimited/" },
}

-- Explicit "radio turned off" sentinel - distinct from ElementData's own
-- "key was never set" (getElementData returns false for an absent key
-- too), so a vehicle nobody has touched yet reads as "never set" ->
-- RadioService.getCurrentStation falls back to STATIONS[1] (see below),
-- while a vehicle someone deliberately silenced stays silent for the next
-- driver instead of springing back to life.
local RADIO_OFF = "off"

--- @return table[] the fixed station list - copies are never mutated by
--         callers (index 0/"off" is represented as nil, not a list entry)
RadioService.getStations = function()
    return STATIONS
end

--- @param vehicle vehicle
-- @return table|nil { name, url } - nil means "off" (either never set, or
--         explicitly turned off - callers that need to tell those apart
--         use hasStationEverBeenSet instead)
RadioService.getCurrentStation = function(vehicle)
    local station = getElementData(vehicle, ElementData.Vehicle.RADIO_STATION)
    return type(station) == "table" and station or nil
end

--- @param vehicle vehicle
-- @return boolean true if this vehicle's radio has ever been touched
--         (playing OR explicitly turned off) - false only for a vehicle
--         nobody has driven with radio controls yet.
RadioService.hasStationEverBeenSet = function(vehicle)
    return getElementData(vehicle, ElementData.Vehicle.RADIO_STATION) ~= false
end

--- Sets `vehicle`'s station and notifies every current occupant.
-- @param vehicle vehicle
-- @param station table|nil { name, url } - nil turns the radio off
RadioService.setStation = function(vehicle, station)
    setElementData(vehicle, ElementData.Vehicle.RADIO_STATION, station or RADIO_OFF)

    for _, occupant in pairs(getVehicleOccupants(vehicle)) do
        triggerClientEvent(occupant, Events.RADIO_STATION_CHANGED, occupant, station)
    end
end

--- @param player element
-- @return vehicle|nil the vehicle `player` is driving, nil if not a driver
local function drivenVehicleOf(player)
    local vehicle = getPedOccupiedVehicle(player)
    if vehicle and getVehicleController(vehicle) == player then
        return vehicle
    end
    return nil
end

addEvent(Events.RADIO_REQUEST_STATIONS, true)
addEventHandler(Events.RADIO_REQUEST_STATIONS, root, function()
    triggerClientEvent(client, Events.RADIO_STATIONS_RECEIVED, client, STATIONS)
end)

addEvent(Events.RADIO_CHANGE_STATION, true)
addEventHandler(Events.RADIO_CHANGE_STATION, root, function(next)
    local player = client
    local vehicle = drivenVehicleOf(player)
    if not vehicle then
        return
    end

    local current = RadioService.getCurrentStation(vehicle)
    local currentIndex = 0
    for index, station in ipairs(STATIONS) do
        if current and station.url == current.url then
            currentIndex = index
            break
        end
    end

    local nextIndex
    if next then
        nextIndex = currentIndex + 1
        if nextIndex > #STATIONS then
            nextIndex = 0
        end
    else
        nextIndex = currentIndex - 1
        if nextIndex < 0 then
            nextIndex = #STATIONS
        end
    end

    RadioService.setStation(vehicle, STATIONS[nextIndex])
end)

addEventHandler("onVehicleEnter", root, function(player, seat)
    -- Driver entering a vehicle whose radio nobody has EVER touched
    -- (not "explicitly off", genuinely untouched) starts it on the first
    -- station automatically. A vehicle someone previously turned off, or
    -- whose station was already set (re-entering after getting out), is
    -- left as-is here - RadioService.setStation already broadcasts
    -- RADIO_STATION_CHANGED to every current occupant on an actual change.
    if seat == 0 and not RadioService.hasStationEverBeenSet(source) then
        RadioService.setStation(source, STATIONS[1])
        return
    end

    -- Every occupant re-entering an already-touched vehicle (driver
    -- returning to their own car, or a passenger joining mid-ride) needs
    -- to be caught up on whatever's already playing (or silence, if it
    -- was turned off) - RADIO_STATION_CHANGED only fires ON CHANGE, so
    -- without this whoever just got in would hear nothing until the next
    -- actual station switch. getCurrentStation returns nil for both
    -- "never set" (already handled above for the driver) and "explicitly
    -- off", which is the correct silence in both remaining cases.
    triggerClientEvent(player, Events.RADIO_STATION_CHANGED, player, RadioService.getCurrentStation(source))
end)
