Config = Config or {}



-- Framework override: nil = auto-detect (QBCore/QBX/ESX), or set to 'qbcore' / 'esx'
Config.Framework = nil


Config.Locale = "en"  -- change to "fr" or "de" as needed


-- Target System: 'ox_target' or 'qb-target'
-- Set this based on which target script your server uses
Config.TargetSystem = 'ox_target'

-- Race start delay in seconds (time before race begins after countdown)
-- Default is 3 for testing, but most players prefer 10 seconds or less
Config.RaceStartDelay = 10

-- How often clients report progress to the server (ms). Lower = more responsive positions.
-- Keep between 75 and 200 to balance responsiveness vs. server load.
Config.ProgressTickMs = 150

-- Use front bumper corners (left/right) in addition to center and take the max
-- along-track distance. Helps tiny nose differences decide position on curves.
Config.DistanceUseNoseCorners = true


-- Debug toggles
Config.DebugPrints = false      -- Console [DEBUG] logs (ranking/progress/etc)

Config.ZoneDebug   = false      -- Polyzone/lib.zones visualization (red spheres)


-- If your in-race positions appear reversed (the car behind shows 1/2),
-- set this to true to invert the displayed rank without changing core sorting.
Config.RankingInvert = false


--- Choose your notification provider: "ox_lib", "okokNotify" or "rtx_notify"
Config.NotificationProvider = "ox_lib"


-- Default keybind for opening lobby controls (players can remap in FiveM bindings)
-- Use FiveM key names, e.g., 'LMENU' (Left Alt), 'F6', 'E', etc.
Config.InteractKey = 'F2'

-- Human-friendly label shown in the UI hint
Config.InteractKeyLabel = 'F2'


--- Built-in Raceway Leaderboard Display (bundled from glitchdetector's amir-leaderboard)
Config.Leaderboard = {
    enabled = true,
    -- Show best times on the board when no race is active
    idleDisplay = true,
    -- How often to push updates to AMIR (ms). Too frequent causes flicker.
    updateIntervalMs = 1000,
    -- How often to flip between Names and Times on the board (ms)
    toggleIntervalMs = 2000,
    -- Display mode for AMIR board rows:
    --  - "toggle": alternate Names and Times every toggleIntervalMs
    --  - "names":  always show player names
    viewMode = "toggle",
    -- What time to show on the AMIR toggle (names/times):
    --  - "total": total race time so far per racer (default)
    --  - "lap": current lap time per racer
    timeMode = "total",
    -- Where the physical sign stands (from stream/amir_speedway_sign.ymap). When a player
    -- comes within signRadius the texture replacement is re-applied, so a sign whose
    -- texture dictionary streamed in after the first attempt still shows the live board.
    signCoords = vector3(-2869.0, 8427.4, 87.7),
    signRadius = 300.0,
    -- Sponsor slides for the three ad panels on the board (paths inside html/).
    adUrls = { "ads/dps_1.png", "ads/dps_2.png", "ads/dps_3.png" },
}


--- GHOSTING (anti-grief collision disabling)
Config.Ghosting = {
    enabled = true,
    startGhosted = true,          -- ghost all racers at GO
    unghostOnCheckpoint = 1,      -- unghost after ALL racers pass this checkpoint (0 = timer only)
    unghostTimerSeconds = 15,     -- fallback timer if checkpoint not reached
    lappedGhosting = true,        -- ghost players a full lap behind leader
    ghostAlpha = 150,             -- transparency when ghosted (0-255)
}


--- RACE RESULTS UI (NUI results screen after race)
Config.ResultsUI = {
    enabled = true,
    displayDurationMs = 20000,    -- auto-dismiss after 20s
    showBestLap = true,
    showMostImproved = true,      -- highlight player who gained most positions
}
