Config = Config or {}




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
