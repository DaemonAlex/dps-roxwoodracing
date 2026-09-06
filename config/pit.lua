Config = Config or {}


Config.PitCrewZones = {
    -- Zone #1 (replace coords with your pit‐lane location)
    {  
      coords = vector3(-2865.45, 8113.30, 43.74),   
      heading = 180.0,    -- NPCs will face south
      radius = 6.0  
    },
  
    -- Zone #2
    {  
      coords = vector3(-2840.76, 8109.64, 43.55),   
      heading = 180.0,    -- NPCs will face south
      radius = 6.0  
    },

    -- Server owners can add more:  
    -- Example zone #3 (replace coords with your pit‐lane location)
    -- {  
      -- coords = vector3(x, y, z),   
      -- heading = 180.0,    -- NPCs will face south
      -- radius = 6.0  
    -- },
}


-- Pit-crew settings
-- Ped models for the crew. Each crew member picks one at random and gets a random
-- outfit variation, so the boxes are not staffed by identical clones. Models that are
-- not present on the client are skipped; if none load, s_m_y_xmech_02 is used.
Config.PitCrewModels = {
    'ig_mechanic_ped_1',   -- addon (ghostic) mechanic, present on DPS
    'ig_mechanic_ped_2',   -- addon (ghostic) mechanic, present on DPS
    's_m_y_xmech_01',      -- vanilla mechanic, coveralls
    's_m_y_xmech_02',      -- vanilla mechanic, coveralls
    's_m_m_autoshop_01',   -- vanilla LS Customs mechanic
    's_m_m_autoshop_02',   -- vanilla LS Customs mechanic
    's_m_y_airworker',     -- vanilla ground crew, hi-vis + ear defenders
    'a_m_y_motox_01',      -- vanilla race suit
    'a_m_y_motox_02',      -- vanilla race suit
    's_m_y_construct_01',  -- the original crew look, kept as one of ten so a box gets one or two
}

Config.PitCrewIdleOffsets = {
    vector3(-2.0,  0.0,  0.0),  -- two idle spots (left/right)
    vector3( 2.0,  0.0,  0.0),
}

Config.PitCrewCrewOffsets = {
    vector3( 0.0, -2.0,  0.0),  -- refuel spot (rear)
    vector3( 0.0,  2.0,  0.0),  -- hood spot (front)
    vector3( 2.0,  0.0,  0.0),  -- jack spot (side)
}


-- Pit Stop Timing (adjust for realism vs speed)
Config.PitStopTiming = {
    crewWalkSpeed    = 2.0,     -- 1.0 = walk, 2.0 = jog, 3.0+ = run
    refuelSteps      = 15,      -- Number of fuel increments (more = smoother fill)
    refuelStepMs     = 200,     -- Milliseconds per refuel step (total = steps * ms)
    repairDuration   = 3000,    -- Milliseconds for repair animation
    approachTimeout  = 8000,    -- Max ms to wait for crew to approach vehicle
    returnTimeout    = 15000,   -- Max ms to wait for crew to return to positions
}


-- Pit Crew Idle Animations (randomly selected for variety)
Config.PitCrewIdleAnims = {
    "WORLD_HUMAN_STAND_IMPATIENT",
    "WORLD_HUMAN_AA_SMOKE",
    "WORLD_HUMAN_CLIPBOARD",
    "WORLD_HUMAN_DRINKING",
}
