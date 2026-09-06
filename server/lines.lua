-- Practice line storage: one row per named line, recorded by a Race Director.
local TABLE = 'dps_roxwoodracing_lines'
Lines = Lines or {}
Lines.TABLE = TABLE
local cache = {}

function Lines.Init()
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS %s (
      name VARCHAR(40) NOT NULL PRIMARY KEY,
      points MEDIUMTEXT NOT NULL,
      point_count INT NOT NULL DEFAULT 0,
      closed TINYINT(1) NOT NULL DEFAULT 0,
      citizenid VARCHAR(60),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  ]]):format(TABLE))
end

function Lines.Save(name, points, info, cid)
  MySQL.query.await(([[
    INSERT INTO %s (name, points, point_count, closed, citizenid) VALUES (?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE points = VALUES(points), point_count = VALUES(point_count),
      closed = VALUES(closed), citizenid = VALUES(citizenid)
  ]]):format(TABLE), { name, json.encode(points), info.count, info.closed and 1 or 0, cid })
end

function Lines.Get(name)
  local row = MySQL.single.await(('SELECT points, point_count, closed FROM %s WHERE name = ?'):format(TABLE), { name })
  if not row then return nil end
  return json.decode(row.points), row.point_count, row.closed == 1
end

function Lines.List()
  return MySQL.query.await(('SELECT name, point_count, closed, created_at FROM %s ORDER BY name'):format(TABLE)) or {}
end

RegisterNetEvent('dps-roxwoodracing:line:save', function(name, points)
  local src = source
  if not Staff.Can(src, 'director') then
    TriggerClientEvent('dps-roxwoodracing:line:saved', src, false, Locale('staff_only'))
    return
  end
  local ok, err, info = Lines.Validate(name, points, Config.Practice)
  if not ok then
    TriggerClientEvent('dps-roxwoodracing:line:saved', src, false, Locale('line_invalid', tostring(err)))
    return
  end
  Lines.Save(name, points, info, Bridge.GetPlayerIdentifier(src))
  cache[name] = nil
  print(('[dps-roxwoodracing] practice line "%s" saved: %d points, %s'):format(name, info.count, info.closed and 'closed loop' or 'open'))
  TriggerClientEvent('dps-roxwoodracing:line:saved', src, true,
    Locale(info.closed and 'line_saved_closed' or 'line_saved_open', name, info.count), name)
end)

-- The line the AI practice cars run (cached until it is re-recorded).
lib.callback.register('dps-roxwoodracing:practice:line', function(_)
  local name = (Config.Practice.ai and Config.Practice.ai.lineName) or 'main'
  if not cache[name] then
    local pts, _, closed = Lines.Get(name)
    if pts then cache[name] = { pts = pts, closed = closed } end
  end
  local c = cache[name]
  if not c then return nil end
  return c.pts, c.closed
end)

lib.callback.register('dps-roxwoodracing:line:list', function(src)
  if not Staff.Can(src, 'marshal') then return nil end
  return Lines.List()
end)

CreateThread(function()
  Lines.Init()
  print(('[dps-roxwoodracing] practice lines: %d stored'):format(#Lines.List()))
end)
