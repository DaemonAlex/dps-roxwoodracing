-- LED signs at the other tracks. A Race Director stands where the sign should be and runs
-- /placesign; the spot is stored per track and every client shows the Roxwood sign model
-- there. The board it shows is the practice order of that track (drawn on each client).
local TABLE = 'dps_roxwoodracing_signs'
Signs = Signs or {}

function Signs.Init()
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS %s (
      track VARCHAR(40) NOT NULL PRIMARY KEY,
      x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, h FLOAT NOT NULL,
      citizenid VARCHAR(60),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ]]):format(TABLE))
end

function Signs.List()
  return MySQL.query.await(('SELECT track, x, y, z, h FROM %s ORDER BY track'):format(TABLE)) or {}
end

local function num(v) return type(v) == 'number' and v == v and math.abs(v) < 1e6 end

RegisterNetEvent('dps-roxwoodracing:sign:place', function(track, x, y, z, h)
  local src = source
  if not Staff.Can(src, 'director') then
    TriggerClientEvent('dps-roxwoodracing:sign:result', src, false, Locale('staff_only')) return
  end
  if type(track) ~= 'string' or not track:match('^[a-z0-9_]+$') or #track > 40
    or not (num(x) and num(y) and num(z) and num(h)) then
    TriggerClientEvent('dps-roxwoodracing:sign:result', src, false, Locale('sign_invalid')) return
  end
  MySQL.query.await(('REPLACE INTO %s (track, x, y, z, h, citizenid) VALUES (?, ?, ?, ?, ?, ?)'):format(TABLE),
    { track, x, y, z, h, Bridge.GetPlayerIdentifier(src) })
  print(('[dps-roxwoodracing] sign placed for %s at %.1f %.1f %.1f'):format(track, x, y, z))
  TriggerClientEvent('dps-roxwoodracing:sign:result', src, true, Locale('sign_placed', track))
  TriggerClientEvent('dps-roxwoodracing:sign:changed', -1)
end)

RegisterNetEvent('dps-roxwoodracing:sign:clear', function(track)
  local src = source
  if not Staff.Can(src, 'director') then
    TriggerClientEvent('dps-roxwoodracing:sign:result', src, false, Locale('staff_only')) return
  end
  if type(track) ~= 'string' then return end
  MySQL.query.await(('DELETE FROM %s WHERE track = ?'):format(TABLE), { track })
  print(('[dps-roxwoodracing] sign removed for %s'):format(track))
  TriggerClientEvent('dps-roxwoodracing:sign:result', src, true, Locale('sign_cleared', track))
  TriggerClientEvent('dps-roxwoodracing:sign:changed', -1)
end)

lib.callback.register('dps-roxwoodracing:sign:list', function(_)
  return Signs.List()
end)

CreateThread(function()
  Signs.Init()
  print(('[dps-roxwoodracing] signs: %d placed'):format(#Signs.List()))
end)
