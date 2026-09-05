dofile('shared/validate.lua'); dofile('shared/plates.lua'); dofile('shared/tune.lua'); dofile('shared/payouts.lua')

local cfg = {
  Checkpoints = { Short_Track = {1,2,3} },
  OpenClasses = { Any = {}, Super = {} },
  Tune = { Stock = { mods = {}, toggles = {} }, Race = { mods = { [11] = 'max' }, toggles = { [18] = true } } },
  SpecClassKeys = { All = true, Super = true },
}

TEST('Validate.CreateArgs accepts a good spec request and defaults', function()
  local ok, err, c = Validate.CreateArgs({ name = 'Sam_1234', track = 'Short_Track', laps = 3 }, cfg)
  TRUTHY(ok, err); EQ(c.mode, 'spec'); EQ(c.class, 'All'); EQ(c.tune, 'Stock'); EQ(c.laps, 3)
end)
TEST('Validate.CreateArgs rejects bad name, track, laps, mode, class', function()
  local ok, err = Validate.CreateArgs({ name = 'bad name!', track = 'Short_Track', laps = 3 }, cfg); FALSY(ok); EQ(err, 'invalid_lobby_name')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Nope', laps = 3 }, cfg); FALSY(ok); EQ(err, 'invalid_track')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 11 }, cfg); FALSY(ok); EQ(err, 'invalid_laps')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'weird' }, cfg); FALSY(ok); EQ(err, 'invalid_mode')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'open', class = 'Muscle' }, cfg); FALSY(ok); EQ(err, 'invalid_class')
  local ok2, _, c = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'open', class = 'Super', tune = 'Race' }, cfg)
  TRUTHY(ok2); EQ(c.tune, 'Stock', 'tune ignored for open')
end)

TEST('Plates.FromName sanitises, trims to 8, uniquifies', function()
  local used = {}
  EQ(Plates.FromName('Sam', "O'Rider", 'rock', used), 'SAMORIDE')
  EQ(Plates.FromName('Sam', "O'Rider", 'rock', used), 'SAMORID1')
  EQ(Plates.FromName(nil, nil, 'rock star', used), 'ROCKSTAR')
  EQ(Plates.FromName(nil, nil, '', used), 'RWR')
end)

TEST('Tune.ModsFor returns preset mods and empty for unknown', function()
  EQ(Tune.ModsFor('Race', cfg).mods[11], 'max'); TRUTHY(Tune.ModsFor('Race', cfg).toggles[18])
  EQ(next(Tune.ModsFor('Nope', cfg).mods), nil)
end)

local economy = { payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, poolSplit = { [1] = 60, [2] = 30, [3] = 10 } }
local results = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }

TEST('Payouts.Compute pays purse + pool when balance covers it', function()
  local p, covered = Payouts.Compute(results, 2, economy, 4000, 100000)
  TRUTHY(covered)
  EQ(p[1].position, 5000); EQ(p[1].participation, 500); EQ(p[1].bestLap, 0); EQ(p[1].pool, 2400); EQ(p[1].total, 7900)
  EQ(p[2].bestLap, 1000); EQ(p[2].pool, 1200); EQ(p[2].total, 3000 + 500 + 1000 + 1200)
  EQ(p[4].position, 0); EQ(p[4].pool, 0); EQ(p[4].total, 500)
  EQ(Payouts.PurseTotal(results, 2, economy), 5000 + 3000 + 1500 + 4 * 500 + 1000)
end)
TEST('Payouts.Compute pays pool only when the account is short', function()
  local p, covered = Payouts.Compute(results, 2, economy, 4000, 100)
  FALSY(covered)
  EQ(p[1].position, 0); EQ(p[1].participation, 0); EQ(p[2].bestLap, 0); EQ(p[1].pool, 2400); EQ(p[1].total, 2400)
end)
