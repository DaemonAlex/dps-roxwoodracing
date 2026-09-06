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
    smoothRadius  = 1,      -- average each point with this many neighbours either side
    smoothPasses  = 1,      -- keep it light: wide windows pull corners toward the inside
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
    -- Driver names shown on the LED sign while practice runs (5 characters read best)
    driverNames    = { 'SANDS', 'PERRO', 'ROX', 'DUNE', 'PIER', 'SURF', 'GULL', 'TIDE' },
    boardTitle     = 'PRAC',
    boardEveryMs   = 1000,
    -- Engine audio names streamed by dps-enginesounds; each car takes a random one.
    -- nil = keep the model's own sound.
    tunePreset     = 'Race',         -- Config.Tune preset applied to each car (max engine/transmission/brakes + turbo)
    topSpeedBoost  = 50,             -- ModifyVehicleTopSpeed percent
    cullRadius     = 6000.0,         -- server-side distance culling radius for each car + driver (OneSync default ~424 m)
    lodDistance    = 3000,           -- render LOD distance (m) so cars stay visible from the tower
    audioPriority  = 3,              -- SetAudioVehiclePriority: 0 normal, 1 medium, 3 high, 2 max (max starves other cars)
    engineSounds   = { 'honf1v6eng', 'lg115classicf1v10', 'frf119eng', 'lg59hurv10', 'lambov10', 'lg48lexlfa' },
    spawnDistance  = 300.0,          -- metres beyond the line's extent that counts as "near"
    cruiseSpeed    = 30.0,           -- m/s fallback when a line has no speed profile
    -- Speed profile from the route geometry (m/s, m/s^2): corner speed = sqrt(aLat x radius),
    -- braking into bends at aBrake, acceleration out at aAccel, flat out elsewhere.
    physics = {
        vmax   = 90.0,               -- above any open-wheeler's real top speed = flat out
        vmin   = 14.0,               -- hairpin floor
        aLat   = 30.0,               -- lateral grip (~3.0 g)
        aBrake = 32.0,               -- braking (~3.2 g)
        aAccel = 20.0,               -- acceleration out of corners
    },
    releaseBehind  = 35,             -- release point: this many points (35 x 12 m = 420 m) before the player
    releaseSpeed   = 30.0,           -- rolling start (m/s) so cars arrive at pace
    staggerMs      = 35000,          -- one car released every 35 s
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
    stuckMs        = 6000,           -- no movement for this long = put it back on the line
    noProgressMs   = 15000,          -- no progress along the line for this long = also stuck (AI reversing at a wall)
    stuckSkipPts   = 8,              -- stuck twice at the same spot: skip this many points past it
    aggressiveness = 1.0,
    paceVariance   = 0.08,           -- each car's pace = cruiseSpeed x (1 +/- this)
    laneJitter     = 1.0,            -- each car keeps its own lateral bias of up to this (m)
    -- Race awareness: slow toward a car ahead inside this window and aim past it
    aware = {
        range          = 35.0,       -- metres ahead to look
        lateral        = 6.0,        -- metres either side that counts as "in my way"
        minSpeed       = 9.0,        -- never crawl slower than this behind someone
        overtakeOffset = 3.5,        -- aim this far to the free side to pass
        passWithin     = 25.0,       -- only start the pass move when the car ahead is this close
        closeGap       = 10.0,       -- lift only when this close behind the car ahead
        closeFactor    = 0.8,        -- ...and only to this fraction of pace
    },
    -- 1 StopForVehicles, 4 SwerveAroundAllVehicles, 16777216 ForceStraightLine (drive
    -- straight at the aim point, no road-node routing). Object/ped steering flags left
    -- out: they make the AI flinch at barriers.
    drivingStyle   = 1 + 4 + 16777216,
}

--- STATIC PIT CARS
-- Placed in game by a Race Director: park where the car should sit and run /pitcar
-- (uses that car's model), or run it on foot for a random model. /pitcar clear removes all.
Config.Practice.pitCars = {
    spawnDistance = 300.0,
    models        = nil,   -- random pool when placed on foot; nil = the AI grid models
    lodDistance   = 3000,  -- render LOD distance (m)
}
