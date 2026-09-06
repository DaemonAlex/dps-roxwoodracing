Config = Config or {}

--- PRACTICE LINES
-- A Race Director drives one clean lap with /recordline <name>; the line is stored in
-- the database and later drives the AI practice cars when no race is running.
Config.Practice = {
    recordSpacing = 12.0,   -- metres between stored points while recording
    minPoints     = 10,     -- shorter recordings are discarded
    maxPoints     = 2000,   -- recording stops itself at this many points
    closeRadius   = 40.0,   -- end within this distance of the start = closed loop
    -- Smoothing applied when the line is served to clients (the recording stays raw):
    smoothRadius  = 3,      -- average each point with this many neighbours either side
    smoothPasses  = 3,
}

--- AI PRACTICE CARS
-- When no race is live and a player is near the track, a few cars lap the recorded line.
-- Scenery: the cars are local to each client (not networked), so they cost the server
-- nothing and vanish the moment a race goes live.
Config.Practice.ai = {
    enabled        = true,
    networked      = true,           -- networked (owned by this client, no migration): engine audio plays; false = purely local
    lineNames      = nil,            -- nil = every stored line; or a list like { 'main', 'wide' }
    variants       = 4,              -- generated variants per stored line (smooth lateral drift)
    varyAmplitude  = 1.5,            -- max metres a variant drifts either side of the recorded line
    cars           = 6,
    -- Open-wheel grid (vanilla). nil = random picks from Config.SpecFallbackVehicles.
    models         = { 'openwheel1', 'openwheel2', 'formula', 'formula2' },
    driverModel    = 'a_m_y_motox_01',
    -- Engine audio names streamed by dps-enginesounds; each car takes a random one.
    -- nil = keep the model's own sound.
    engineSounds   = { 'honf1v6eng', 'lg115classicf1v10', 'frf119eng', 'lg59hurv10', 'lambov10', 'lg48lexlfa' },
    spawnDistance  = 300.0,          -- metres beyond the line's extent that counts as "near"
    cruiseSpeed    = 30.0,           -- m/s fallback when a line has no speed profile
    -- Speed profile from the line's shape (m/s): straights run topSpeed, a bend of
    -- fullTurnDeg or more over ~36 m runs cornerSpeed, braking starts brakePoints early
    topSpeed       = 60.0,           -- ~216 km/h
    cornerSpeed    = 18.0,           -- ~65 km/h
    brakePoints    = 8,              -- points (5 x 12 m) before a corner to start slowing
    fullTurnDeg    = 35,
    releaseBehind  = 12,             -- release point: this many points (12 x 12 m) before the player
    staggerMs      = 40000,          -- one car released every 40 s
    -- Aim point: `aimSeconds` of travel ahead of the car's progress on the line, clamped to
    -- aimMinPts..aimMaxPts points (12 m each). Re-issued when it moves retargetStep points.
    aimSeconds     = 2.0,
    aimMinPts      = 4,
    aimMaxPts      = 14,
    aimMaxTurnDeg  = 25,             -- never aim past where the line has bent more than this
    aimMaxCut      = 1.5,            -- the straight to the aim point may leave the line by at most this (m)
    aimCornerPts   = 2,              -- shortest aim inside a bend (points)
    retargetStep   = 2,
    stopRange      = 2.0,
    tickMs         = 250,            -- steering tick while cars are up
    stuckMs        = 8000,           -- no movement for this long = put it back on the line
    aggressiveness = 0.6,
    paceVariance   = 0.08,           -- each car's pace = cruiseSpeed x (1 +/- this)
    laneJitter     = 1.0,            -- each car keeps its own lateral bias of up to this (m)
    -- Race awareness: slow toward a car ahead inside this window and aim past it
    aware = {
        range          = 50.0,       -- metres ahead to look
        lateral        = 6.0,        -- metres either side that counts as "in my way"
        minSpeed       = 9.0,        -- never crawl slower than this behind someone
        overtakeOffset = 3.5,        -- aim this far to the free side to pass
        passWithin     = 25.0,       -- only start the pass move when the car ahead is this close
    },
    -- 1 StopForVehicles, 4 SwerveAroundAllVehicles, 16777216 ForceStraightLine (drive
    -- straight at the aim point, no road-node routing). Object/ped steering flags left
    -- out: they make the AI flinch at barriers.
    drivingStyle   = 1 + 4 + 16777216,
}
