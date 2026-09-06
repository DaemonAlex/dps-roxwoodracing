-- Static display cars in the pit area. A Race Director parks a car and runs /pitcar;
-- the spot (model, position, heading) is stored and every client shows a frozen car there.
local TABLE = 'dps_roxwoodracing_pitcars'
PitCars = PitCars or {}

function PitCars.Init()
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS %s (
      id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      model VARCHAR(40) NOT NULL,
      x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, h FLOAT NOT NULL,
      citizenid VARCHAR(60),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ]]):format(TABLE))
end

function PitCars.List()
  return MySQL.query.await(('SELECT id, model, x, y, z, h FROM %s ORDER BY id'):format(TABLE)) or {}
end

local function num(v) return type(v) == 'number' and v == v and math.abs(v) < 1e6 end

RegisterNetEvent('dps-roxwoodracing:pitcar:add', function(model, x, y, z, h)
  local src = source
  if not Staff.Can(src, 'director') then
    TriggerClientEvent('dps-roxwoodracing:pitcar:result', src, false, Locale('staff_only')) return
  end
  if type(model) ~= 'string' or not model:match('^[a-z0-9_]+$') or #model > 40
    or not (num(x) and num(y) and num(z) and num(h)) then
    TriggerClientEvent('dps-roxwoodracing:pitcar:result', src, false, Locale('pitcar_invalid')) return
  end
  MySQL.insert.await(('INSERT INTO %s (model, x, y, z, h, citizenid) VALUES (?, ?, ?, ?, ?, ?)'):format(TABLE),
    { model, x, y, z, h, Bridge.GetPlayerIdentifier(src) })
  local n = #PitCars.List()
  print(('[dps-roxwoodracing] pit car added: %s at %.1f %.1f %.1f (%d total)'):format(model, x, y, z, n))
  TriggerClientEvent('dps-roxwoodracing:pitcar:result', src, true, Locale('pitcar_added', model, n))
  TriggerClientEvent('dps-roxwoodracing:pitcar:changed', -1)
end)

RegisterNetEvent('dps-roxwoodracing:pitcar:clear', function()
  local src = source
  if not Staff.Can(src, 'director') then
    TriggerClientEvent('dps-roxwoodracing:pitcar:result', src, false, Locale('staff_only')) return
  end
  MySQL.query.await(('DELETE FROM %s'):format(TABLE))
  print('[dps-roxwoodracing] pit cars cleared')
  TriggerClientEvent('dps-roxwoodracing:pitcar:result', src, true, Locale('pitcar_cleared'))
  TriggerClientEvent('dps-roxwoodracing:pitcar:changed', -1)
end)

lib.callback.register('dps-roxwoodracing:pitcar:list', function(_)
  return PitCars.List()
end)

CreateThread(function()
  PitCars.Init()
  print(('[dps-roxwoodracing] pit cars: %d stored'):format(#PitCars.List()))
end)
