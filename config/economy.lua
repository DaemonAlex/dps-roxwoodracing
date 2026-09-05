Config = Config or {}


--- REWARDS SYSTEM
Config.Rewards = {
    enabled = true,
    moneyType = 'cash',              -- 'cash' or 'bank'
    -- Position-based cash payouts
    payouts = {
        [1] = 5000,
        [2] = 3000,
        [3] = 1500,
    },
    participationReward = 500,       -- Everyone who finishes gets this
    bestLapBonus = 1000,             -- Bonus for fastest lap in the race
    -- 1st place prize vehicles (nil = no vehicle prize, set model name to enable)
    vehiclePrize = nil,              -- e.g. 'krieger' — awarded to 1st place, saved to garage
    vehiclePrizeGarage = 'pillboxgarage', -- which garage to store it in
}


--- ENTRY FEE / PRIZE POOL
Config.EntryFee = {
    enabled = false,                 -- Toggle entry fees on/off
    amount = 1000,                   -- Cost to join a race
    moneyType = 'cash',             -- 'cash' or 'bank'
    -- Prize pool split (percentages, must total 100 or less)
    poolSplit = {
        [1] = 60,                    -- 1st gets 60% of pool
        [2] = 30,                    -- 2nd gets 30%
        [3] = 10,                    -- 3rd gets 10%
    },
}


--- PERSISTENT RACE STATS
Config.Stats = {
    enabled = true,
    showAfterRace = true,            -- Show personal stats summary after each race
}

Config.Job = {
  name   = 'roxwoodracing',
  label  = 'Roxwood Raceway',
  grades = { marshal = 0, pitcrew = 1, director = 2, owner = 3 },
  -- Boss menu zone at the paddock office (next to the lobby ped)
  bossCoords = vector3(-2903.5, 8079.2, 44.5),
}

Config.Economy = {
  purseSource = 'society',          -- 'society' (pay from the job account) | 'house' (mint, but log)
  entryFee    = { enabled = true, amount = 1000 },
  poolSplit   = { [1] = 60, [2] = 30, [3] = 10 },
  payouts     = { [1] = 5000, [2] = 3000, [3] = 1500 },
  participationReward = 500,
  bestLapBonus        = 1000,
  vehiclePrize        = nil,        -- e.g. 'sultan3'; nil = off
  prizeGarage         = 'Roxwood Raceway',
  moneyType           = 'cash',     -- player side of every transaction
}
