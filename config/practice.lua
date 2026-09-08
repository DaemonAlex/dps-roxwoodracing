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

--- TRACKS
-- Stored lines cluster into tracks by location: a line joins a track when its centre lies
-- within this many metres of the track's centre. Each track gets its own zone, host, grid,
-- start line and lap clock, so a second circuit only needs its own /recordline.
Config.Practice.trackJoinRadius = 1500.0
-- Map blip per track (sprite 315), placed at the track centre. The raceway nearest the LED
-- sign keeps its paddock blip from the lobby NPC instead. Names by track id (the base name
-- of the track's first recorded line); an id without an entry shows as "<Id> Raceway".
Config.Practice.trackBlips = {
    enabled = true,
    names   = { grandsenora = 'Grand Senora Raceway', lossantos = 'Los Santos Circuit' },
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
    varyAmplitude  = 0.8,            -- max metres a variant drifts either side of the recorded line
    cars           = 6,
    -- Open-wheel grid (vanilla). nil = random picks from Config.SpecFallbackVehicles.
    models         = { 'openwheel1', 'openwheel2', 'formula', 'formula2' },
    -- Per-track grids, by track id (the base name of the track's first recorded line). A
    -- track without an entry runs `models` / `engineSounds`. Sounds are library bank names
    -- from dps-racesounds; a track listed here with no sounds keeps each car's own bank.
    perTrack = {
        -- Roxwood Raceway (track id = its first line, 'main'): open-wheelers, Hypercars, GT3, NASCAR in rotation
        main = {
            sets = {
                { label = 'Open Wheel', models = { 'openwheel1', 'openwheel2', 'formula', 'formula2' } },
                { label = 'Hypercar',   models = { 'alplmu2025', 'amrlmh', 'bmwlmu2025', 'fer49p2025', 'peulmu2025', 'toyotaGR2025' }, engineSounds = false },
                { label = 'GT3',        models = { 'sg720sgt3', 'sgamggt3', 'sgfordgt3', 'sgngtrgt3', 'sgr8lmsevo', '296gt3' }, engineSounds = false },
                { label = 'NASCAR',     models = { 'nextgen', 'camrynascar', 'fusionnas', 'hotring' }, engineSounds = { 'lg44nascarv8' } },
                { label = 'Superbike',  models = { 'bati', 'bati2', 'hakuchou2', 'akuma', 'carbonrs', 'double', 'vortex', 'defiler', 'hakuchou', 'shinobi', 'reever' } },
                { label = 'Classics', models = { 'stinger', 'ztype', 'torero', 'cheetah2', 'infernus2', 'turismo2', 'jb700', 'mamba', 'coquette2', 'rapidgt3', 'retinue', 'gt500', 'viseris', 'savestra', 'michelli', 'swinger', 'nebula', 'zion3', 'dynasty', 'peyote3', 'coquette3', 'monroe', 'casco', 'feltzer3', 'btype', 'cheburek', 'fagaloa' } },
                { label = 'Retro Racing', models = { 'torero', 'cheetah2', 'retinue', 'gt500', 'rapidgt3', 'cheburek', 'tampa2', 'jester3', 'sultan2', 'hotring', 'ellie', 'dominator3', 'gauntlet3', 'stingergt', 'coquette3', 'infernus2', 'turismo2', 'viseris' } },
            },
        },
        -- Los Santos Circuit (Vinewood track): GT3 grid, each car on its own engine bank
        -- (engineSounds = false keeps the model's own sound), road-course limits.
        lossantos = {
            -- One set is drawn each time the grid forms. engineSounds = false keeps each
            -- car's own bank; a list forces those banks on the set.
            sets = {
                { label = 'GT3',       models = { 'sg720sgt3', 'sgamggt3', 'sgfordgt3', 'sgngtrgt3', 'sgr8lmsevo', '296gt3' }, engineSounds = false },
                { label = 'Hypercar',  models = { 'alplmu2025', 'amrlmh', 'bmwlmu2025', 'fer49p2025', 'peulmu2025', 'toyotaGR2025' }, engineSounds = false },
                { label = 'Touring',   models = { '2017M4DTM', 'castrolsupra', 'Mirage', 'fmjb' }, engineSounds = false },
                { label = 'Trucks', models = { 'trophytruck', 'trophytruck2', 'sandking', 'sandking2', 'rebel2', 'kamacho', 'riata', 'everon', 'caracara2', 'hellion', 'freecrawler', 'dune', 'bifta', 'brawler', 'vagrant', 'outlaw', 'yosemite2', 'yosemite3', 'mesa3', 'bodhi2', 'ratel', 'boor' } },
                { label = 'Open Wheel', models = { 'openwheel1', 'openwheel2', 'formula', 'formula2' } },
                { label = 'Superbike',  models = { 'bati', 'bati2', 'hakuchou2', 'akuma', 'carbonrs', 'double', 'vortex', 'defiler', 'hakuchou', 'shinobi', 'reever' } },
                { label = 'Classics', models = { 'stinger', 'ztype', 'torero', 'cheetah2', 'infernus2', 'turismo2', 'jb700', 'mamba', 'coquette2', 'rapidgt3', 'retinue', 'gt500', 'viseris', 'savestra', 'michelli', 'swinger', 'nebula', 'zion3', 'dynasty', 'peyote3', 'coquette3', 'monroe', 'casco', 'feltzer3', 'btype', 'cheburek', 'fagaloa' } },
                { label = 'Retro Racing', models = { 'torero', 'cheetah2', 'retinue', 'gt500', 'rapidgt3', 'cheburek', 'tampa2', 'jester3', 'sultan2', 'hotring', 'ellie', 'dominator3', 'gauntlet3', 'stingergt', 'coquette3', 'infernus2', 'turismo2', 'viseris' } },
            },
            models       = { 'sg720sgt3', 'sgamggt3', 'sgfordgt3', 'sgngtrgt3', 'sgr8lmsevo', '296gt3' },
            engineSounds = false,
            cars         = 8,
            staggerMs    = 20000,
            physics      = { vmax = 92.0, vmin = 18.0, aLat = 17.0, aBrake = 24.0, aAccel = 24.0 },
            cruiseSpeed  = 50.0,
            tunePreset   = 'Race',
            topSpeedBoost = 10,
            paceVariance = 0.12,
            aware = {
                range = 40.0, lateral = 6.0, minSpeed = 12.0, overtakeOffset = 3.2, passWithin = 30.0,
                closeGap = 7.0, closeLateral = 2.5, closeFactor = 0.92,
                slipRange = 30.0, slipLateral = 3.0, slipBonus = 1.09,
                lateBrakeRange = 25.0, lateBrakeFactor = 1.04,
                defendRange = 20.0, defendOffset = 2.5, bendLookahead = 5,
            },
            aimSeconds   = 1.6,
            aimMinPts    = 3,
            aimCornerPts = 2,
            aimMaxTurnDeg = 22,
            aimMaxCut    = 0.7,
            laneJitter   = 0.3,
            variants     = 6,
            varyAmplitude = 1.8,
            varyCornerScale = 0.2,
        },
        grandsenora = {
            sets = {
                { label = 'NASCAR',    models = { 'nextgen', 'camrynascar', 'fusionnas' }, engineSounds = { 'lg44nascarv8' } },
                { label = 'Stock Car', models = { 'nextgen', 'camrynascar', 'fusionnas', 'hotring' }, engineSounds = { 'lg44nascarv8' } },
                { label = 'Trucks', models = { 'trophytruck', 'trophytruck2', 'sandking', 'sandking2', 'rebel2', 'kamacho', 'riata', 'everon', 'caracara2', 'hellion', 'freecrawler', 'dune', 'bifta', 'brawler', 'vagrant', 'outlaw', 'yosemite2', 'yosemite3', 'mesa3', 'bodhi2', 'ratel', 'boor' } },
                { label = 'Hypercar',  models = { 'alplmu2025', 'amrlmh', 'bmwlmu2025', 'fer49p2025', 'peulmu2025', 'toyotaGR2025' }, engineSounds = false },
                { label = 'GT3',       models = { 'sg720sgt3', 'sgamggt3', 'sgfordgt3', 'sgngtrgt3', 'sgr8lmsevo', '296gt3' }, engineSounds = false },
            },
            models       = { 'nextgen', 'camrynascar', 'fusionnas' },
            engineSounds = { 'lg44nascarv8' },
            -- Stock cars on a short oval: lower cornering and braking limits than the
            -- open-wheelers, gentler aim, a slower fallback cruise.
            physics      = { vmax = 100.0, vmin = 30.0, aLat = 15.0, aBrake = 18.0, aAccel = 32.0 },
            -- Racing each other: more pace spread, a stronger tow, later braking on attack,
            -- a wider pass move and a firmer door on defence.
            paceVariance = 0.12,
            aware = {
                range = 40.0, lateral = 6.0, minSpeed = 12.0, overtakeOffset = 3.2, passWithin = 30.0,
                closeGap = 7.0, closeLateral = 2.5, closeFactor = 0.92,
                slipRange = 30.0, slipLateral = 3.0, slipBonus = 1.09,
                lateBrakeRange = 25.0, lateBrakeFactor = 1.10,
                defendRange = 20.0, defendOffset = 2.5, bendLookahead = 5,
            },
            -- Six lines spread up to 2 m across the straights, pinched to 15% of that in the bends.
            variants     = 6,
            varyAmplitude = 2.0,
            varyCornerScale = 0.15,
            cruiseSpeed  = 60.0,
            -- Stock power: no Race tune and no top-speed boost on a 1,500 kg car, the grip
            -- cannot carry it. Longer, smoother aim so the driver stops sawing at the wheel.
            tunePreset   = Race,
            topSpeedBoost = 15,
            aimSeconds   = 1.4,
            aimMinPts    = 3,
            aimCornerPts = 2,
            aimMaxTurnDeg = 20,
            aimMaxCut    = 0.5,
            laneJitter   = 0.2,
        },
    },
    driverModel    = 'a_m_y_motox_01',
    -- Driver names shown on the LED sign while practice runs (5 characters read best)
    driverNames    = { 'SANDS', 'PERRO', 'ROX', 'DUNE', 'PIER', 'SURF', 'GULL', 'TIDE' },
    boardTitle     = 'PRAC',
    boardEveryMs   = 1000,
    -- Engine audio names streamed by dps-enginesounds; each car takes a random one.
    -- nil = keep the model's own sound.
    tunePreset     = 'Race',         -- Config.Tune preset applied to each car (max engine/transmission/brakes + turbo)
    topSpeedBoost  = 100,            -- ModifyVehicleTopSpeed percent (the only power lever that holds without per-frame calls)
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
        aLat   = 34.0,               -- lateral grip (~3.4 g)
        aBrake = 36.0,               -- braking (~3.6 g)
        aAccel = 26.0,               -- acceleration out of corners
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
    aimMaxCut      = 1.0,            -- the straight to the aim point may leave the line by at most this (m)
    aimCornerPts   = 2,              -- shortest aim inside a bend (points)
    retargetStep   = 2,
    stopRange      = 2.0,
    tickMs         = 250,            -- steering tick while cars are up
    stuckMs        = 6000,           -- no movement for this long = put it back on the line
    noProgressMs   = 15000,          -- no progress along the line for this long = also stuck (AI reversing at a wall)
    stuckSkipPts   = 8,              -- stuck twice at the same spot: skip this many points past it
    aggressiveness = 1.0,
    paceVariance   = 0.08,           -- each car's pace = cruiseSpeed x (1 +/- this)
    laneJitter     = 0.3,            -- each car keeps its own lateral bias of up to this (m)
    -- Race awareness: slow toward a car ahead inside this window and aim past it
    aware = {
        range          = 35.0,       -- metres ahead to look
        lateral        = 6.0,        -- metres either side that counts as "in my way"
        minSpeed       = 9.0,        -- never crawl slower than this behind someone
        overtakeOffset = 2.5,        -- aim this far to the free side to pass
        passWithin     = 25.0,       -- only start the pass move when the car ahead is this close
        closeGap       = 7.0,        -- lift only when this close behind the car ahead
        closeLateral   = 2.5,        -- ...and only when directly behind it
        closeFactor    = 0.9,        -- ...and only to this fraction of pace
        slipRange      = 25.0,       -- slipstream: within this behind a car on the same line
        slipLateral    = 3.0,
        slipBonus      = 1.06,       -- ...run this much over pace
        lateBrakeRange = 20.0,       -- attacking within this: brake later than the profile
        lateBrakeFactor = 1.05,
        defendRange    = 18.0,       -- a car this close behind on a straight gets the door closed
        defendOffset   = 2.5,
        bendLookahead  = 6,          -- points ahead used to judge the next corner (6 x 12 m)
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

--- PRACTICE MODE (players on the track outside a race)
Config.Practice.mode = {
    startRadius   = 15.0,    -- start-line trigger radius (m) around the line's first point
    minLapMs      = 20000,   -- laps outside this window are ignored
    maxLapMs      = 600000,
    keepLaps      = 5,       -- rolling average over this many laps
    -- AI pace against the best rolling average among players on the track:
    defaultPace   = 1.0,     -- grid pace when nobody on the track has an average yet
    margin        = 0.12,    -- AI aims to lap this fraction quicker than that average
    minPace       = 1.00,
    maxPace       = 1.35,    -- the AI may run beyond the physics profile; the human edge is the edge
    clearMargin   = 60.0,    -- players within line extent + this (m) are moved off at GO
}
