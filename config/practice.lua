Config = Config or {}

--- PRACTICE LINES
-- A Race Director drives one clean lap with /recordline <name>; the line is stored in
-- the database and later drives the AI practice cars when no race is running.
Config.Practice = {
    recordSpacing = 12.0,   -- metres between stored points while recording
    minPoints     = 10,     -- shorter recordings are discarded
    maxPoints     = 2000,   -- recording stops itself at this many points
    closeRadius   = 40.0,   -- end within this distance of the start = closed loop
}

--- AI PRACTICE CARS
-- When no race is live and a player is near the track, a few cars lap the recorded line.
-- Scenery: the cars are local to each client (not networked), so they cost the server
-- nothing and vanish the moment a race goes live.
Config.Practice.ai = {
    enabled        = true,
    lineName       = 'main',         -- recorded with /recordline <name>
    cars           = 6,
    -- Open-wheel grid (vanilla). nil = random picks from Config.SpecFallbackVehicles.
    models         = { 'openwheel1', 'openwheel2', 'formula', 'formula2' },
    driverModel    = 'a_m_y_motox_01',
    spawnDistance  = 300.0,          -- metres beyond the line's extent that counts as "near"
    cruiseSpeed    = 30.0,           -- m/s (~108 km/h)
    gridSpacing    = 4,              -- points between grid cars at spawn (4 x 12 m)
    lookahead      = 3,              -- target this many points ahead (3 x 12 m)
    reachRadius    = 20.0,           -- advance the target when this close to it
    stopRange      = 2.0,
    tickMs         = 250,            -- steering tick while cars are up
    stuckMs        = 8000,           -- no movement for this long = put it back on the line
    aggressiveness = 0.4,
    -- 4 swerve cars, 8 steer round stationary cars, 16 steer round peds, 32 steer round
    -- objects, 512 may drive into oncoming, 134217728 force straight line (no road nodes)
    drivingStyle   = 4 + 8 + 16 + 32 + 512 + 134217728,
}
