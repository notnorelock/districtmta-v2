-- Resource-local per-category config: vehicle model, upfront fee (0 =
-- free), friendly name, and the exam marker/start/return positions +
-- checkpoint route. Not in Enums.lua (see core_shared/shared/Enums.lua's
-- own LicenseCategory comment) - nothing outside gm_licenses reads this table.
--
-- Only category B has real (placeholder) route content in v1 - A/C/D
-- have fee/name/vehicle model filled in but NO route (route = nil), so
-- LicenseExamService.lua's marker-creation loop simply skips spawning a
-- marker for them until real coordinates + a route are added - no code
-- changes needed later, just filling in this table.
LicenseCategories = {
    [Enums.LicenseCategory.A] = {
        name = "Prawo jazdy kat. A (Motocykl)",
        vehicleModel = 461,
        fee = 500,
        route = nil,
    },
    [Enums.LicenseCategory.B] = {
        name = "Prawo jazdy kat. B (Samochód)",
        vehicleModel = 602, -- PLACEHOLDER: generic sedan, swap for the real driving-school car model
        fee = 0,            -- category B is free, matching the reference script
        route = {
            -- PLACEHOLDER COORDINATES - TODO: replace with real map
            -- positions before shipping. Every position below is a small
            -- offset from {0,0,3}, not a real spot on the map.
            markerPosition = { x=2121.89,y=-1779.53,z=13.39, interior = 0, dimension = 0 },
            startPosition = { x=2023.61,y=-1749.38,z=13.38, heading = 90 },
            -- Currently UNUSED - finishExam (LicenseExamService.lua) restores
            -- the player's own captured pre-exam position/interior/dimension
            -- instead (more correct: works regardless of where the player
            -- actually started from, and actually restores interior/
            -- dimension, which this field has no way to express). Left here
            -- in case a future design wants a fixed return spot again.
            returnPosition = { x=2081.64,y=-1831.46,z=13.38, heading = 0 },
            examinerSkin = 264, -- PLACEHOLDER companion-ped model
            checkpoints = {
                -- Ordered array - every entry is kind = "standard" in v1.
                -- A future maneuver kind (parking/slalom/obstacle) can be
                -- added later without restructuring LicenseExamService.lua's
                -- state machine - onCheckpointHit can branch on cp.kind
                -- once a second kind exists.
                { kind = "standard", position = { x=2065.23,y=-1749.30,z=13.39 }, radius = 3, objective = "Jedź prosto do pierwszego zakrętu." },
                { kind = "standard", position = { x=2100.32,y=-1734.12,z=13.40 }, radius = 3, objective = "Skręć w prawo." },
                { kind = "standard", position = { x=2114.91,y=-1472.45,z=23.82 }, radius = 3, objective = "Skręć w lewo na następnym skrzyżowaniu." },
            },
            -- Free-driving finish: after the last checkpoint, drive this
            -- many meters (server-accumulated, see LicenseExamService.lua's
            -- own distance tracker) to pass.
            freeDriveDistanceMeters = 150,
        },
    },
    [Enums.LicenseCategory.C] = {
        name = "Prawo jazdy kat. C (Ciężarówka)",
        vehicleModel = 403,
        fee = 750,
        route = nil,
    },
    [Enums.LicenseCategory.D] = {
        name = "Prawo jazdy kat. D (Autobus)",
        vehicleModel = 437,
        fee = 1000,
        route = nil,
    },
}
