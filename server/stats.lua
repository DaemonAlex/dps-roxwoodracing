Stats = {}
Stats.TABLE = 'dps_roxwoodracing_stats'

local function tableExists(name)
  local n = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name })
  return (tonumber(n) or 0) > 0
end

function Stats.Migrate()
  if not (Config.Stats and Config.Stats.enabled) then return end
  local oldExists, newExists = tableExists('speedway_stats'), tableExists(Stats.TABLE)
  if oldExists and not newExists then
    MySQL.query.await(('RENAME TABLE speedway_stats TO %s'):format(Stats.TABLE))
    print('[dps-roxwoodracing] stats: renamed speedway_stats -> ' .. Stats.TABLE)
  end
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS %s (
      citizenid VARCHAR(50) NOT NULL,
      total_races INT DEFAULT 0,
      wins INT DEFAULT 0,
      top3 INT DEFAULT 0,
      total_earnings INT DEFAULT 0,
      best_laps JSON DEFAULT '{}',
      last_race TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (citizenid)
    )]]):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS spec_wins INT DEFAULT 0'):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS open_wins INT DEFAULT 0'):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS practice_best_ms INT DEFAULT NULL'):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS practice_laps INT DEFAULT 0'):format(Stats.TABLE))
  MySQL.query.await(("ALTER TABLE %s ADD COLUMN IF NOT EXISTS practice_recent VARCHAR(255) DEFAULT '[]'"):format(Stats.TABLE))
  print('[dps-roxwoodracing] stats: table ready')
end

function Stats.MergeBestLap(bestLaps, track, lap)
  bestLaps = bestLaps or {}
  if lap and lap > 0 and (not bestLaps[track] or lap < bestLaps[track]) then
    bestLaps[track] = lap
    return bestLaps, true
  end
  return bestLaps, false
end

function Stats.Save(pid, position, track, bestLap, earnings, mode)
  if not (Config.Stats and Config.Stats.enabled) then return end
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid then return end
  local isWin = position == 1 and 1 or 0
  local isTop3 = position <= 3 and 1 or 0
  local specWin = (isWin == 1 and mode ~= 'open') and 1 or 0
  local openWin = (isWin == 1 and mode == 'open') and 1 or 0
  earnings = earnings or 0
  local existing = MySQL.single.await(('SELECT total_races, wins, best_laps FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  local bestLaps, prevRaces, prevWins = {}, 0, 0
  if existing then
    bestLaps = json.decode(existing.best_laps or '{}') or {}
    prevRaces, prevWins = existing.total_races or 0, existing.wins or 0
  end
  local newRecord
  bestLaps, newRecord = Stats.MergeBestLap(bestLaps, track, bestLap)
  local encoded = json.encode(bestLaps)
  MySQL.query.await(([[
    INSERT INTO %s (citizenid, total_races, wins, top3, total_earnings, best_laps, spec_wins, open_wins, last_race)
    VALUES (?, 1, ?, ?, ?, ?, ?, ?, NOW())
    ON DUPLICATE KEY UPDATE
      total_races = total_races + 1, wins = wins + ?, top3 = top3 + ?, total_earnings = total_earnings + ?,
      best_laps = ?, spec_wins = spec_wins + ?, open_wins = open_wins + ?, last_race = NOW()]]):format(Stats.TABLE),
    { cid, isWin, isTop3, earnings, encoded, specWin, openWin, isWin, isTop3, earnings, encoded, specWin, openWin })
  if newRecord then TriggerEvent('dps-roxwoodracing:recordSet') end
  if Config.Stats.showAfterRace then
    TriggerClientEvent('dps-roxwoodracing:client:statsNotify', pid, {
      wins = prevWins + isWin, totalRaces = prevRaces + 1, bestLap = bestLaps[track], newRecord = newRecord and bestLap or nil,
    })
  end
end

--- Rolling practice average for a citizen (ms) or nil.
function Stats.PracticeAvg(cid)
  local row = MySQL.single.await(('SELECT practice_recent FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  if not row then return nil end
  local recent = json.decode(row.practice_recent or '[]') or {}
  if #recent == 0 then return nil end
  local _, avg = Practice.RollingAvg(recent, nil, #recent + 1)
  return avg
end

--- Record a practice lap. Returns best (ms), avg (ms), isNewBest, laps.
function Stats.SavePracticeLap(cid, ms, keep)
  local row = MySQL.single.await(('SELECT practice_best_ms, practice_laps, practice_recent FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  local recent = row and (json.decode(row.practice_recent or '[]') or {}) or {}
  local newRecent, avg = Practice.RollingAvg(recent, ms, keep or 5)
  local prevBest = row and row.practice_best_ms or nil
  local isBest = (not prevBest) or ms < prevBest
  local best = isBest and ms or prevBest
  local laps = ((row and row.practice_laps) or 0) + 1
  MySQL.query.await(([[
    INSERT INTO %s (citizenid, practice_best_ms, practice_laps, practice_recent) VALUES (?, ?, 1, ?)
    ON DUPLICATE KEY UPDATE practice_best_ms = ?, practice_laps = practice_laps + 1, practice_recent = ?]]):format(Stats.TABLE),
    { cid, best, json.encode(newRecent), best, json.encode(newRecent) })
  return best, avg, isBest, laps
end

lib.callback.register('dps-roxwoodracing:getPlayerStats', function(source)
  local cid = Bridge.GetPlayerIdentifier(source)
  if not cid then return nil end
  local row = MySQL.single.await(('SELECT * FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  if not row then return nil end
  row.best_laps = json.decode(row.best_laps or '{}') or {}
  return row
end)

CreateThread(Stats.Migrate)
