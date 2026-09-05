TEST('MergeBestLap records only faster laps', function()
  RESET_STUB(); Config = { Stats = { enabled = true, showAfterRace = false } }; Bridge = { GetPlayerIdentifier = function() return 'C1' end }
  dofile('server/stats.lua')
  local bl, rec = Stats.MergeBestLap({ Short_Track = 50000 }, 'Short_Track', 48000); TRUTHY(rec); EQ(bl.Short_Track, 48000)
  bl, rec = Stats.MergeBestLap(bl, 'Short_Track', 49000); FALSY(rec); EQ(bl.Short_Track, 48000)
  bl, rec = Stats.MergeBestLap(bl, 'Long_Track', 0); FALSY(rec)
end)

TEST('Migrate renames the old table when only it exists', function()
  RESET_STUB(); Config = { Stats = { enabled = true } }; Bridge = {}
  local seq, i = { 1, 0 }, 0
  local orig = MySQL.scalar.await
  MySQL.scalar.await = function(sql, params) i = i + 1; STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return seq[i] end
  dofile('server/stats.lua')
  MySQL.scalar.await = orig
  local renamed = false
  for _, q in ipairs(STUB.queries) do if q.sql:find('RENAME TABLE') then renamed = true end end
  TRUTHY(renamed)
end)

TEST('Save upserts with mode counters', function()
  RESET_STUB(); Config = { Stats = { enabled = true, showAfterRace = false } }; Bridge = { GetPlayerIdentifier = function() return 'C1' end }
  STUB.scalar = 0
  dofile('server/stats.lua')
  STUB.row = { total_races = 2, wins = 1, best_laps = '{"Short_Track":50000}' }
  Stats.Save(7, 1, 'Short_Track', 48000, 7900, 'open')
  local q = STUB.queries[#STUB.queries]
  TRUTHY(q.sql:find('open_wins'), 'open_wins column in upsert')
  EQ(q.params[1], 'C1')
end)
