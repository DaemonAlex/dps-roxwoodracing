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
  local closed = row.closed == 1 or row.closed == true or row.closed == '1'
  return json.decode(row.points), row.point_count, closed
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

-- The lines the AI practice cars run (all stored lines, or Config.Practice.ai.lineNames),
-- smoothed and cached until a line is re-recorded.
lib.callback.register('dps-roxwoodracing:practice:lines', function(_)
  local names = Config.Practice.ai and Config.Practice.ai.lineNames
  if not names then
    names = {}
    for _, r in ipairs(Lines.List()) do names[#names + 1] = r.name end
  end
  local out = {}
  for _, name in ipairs(names) do
    if not cache[name] then
      local pts, _, closed = Lines.Get(name)
      if pts then
        local raw = #pts
        if closed then pts = Lines.TrimClosure(pts, Config.Practice.recordSpacing or 12.0, 40) end
        print(('[dps-roxwoodracing] practice line "%s": %d points (%d after closure trim), closed=%s'):format(name, raw, #pts, tostring(closed)))
        pts = Lines.Smooth(pts, Config.Practice.smoothRadius or 2, Config.Practice.smoothPasses or 2, closed)
        local ai = Config.Practice.ai or {}
        local set = { { name = name, pts = pts, closed = closed } }
        for k = 1, (ai.variants or 0) do
          set[#set + 1] = { name = ('%s#%d'):format(name, k), closed = closed,
            pts = Lines.Vary(pts, k * 7919 + #pts, ai.varyAmplitude or 2.5, closed) }
        end
        for _, L in ipairs(set) do
          Lines.SpeedProfilePhysics(L.pts, closed, ai.physics or {})
        end
        cache[name] = set
      end
    end
    for _, L in ipairs(cache[name] or {}) do out[#out + 1] = L end
  end
  return out
end)

-- Practice cars are client-owned networked entities that run a 4 km lap; OneSync culls
-- a networked entity more than ~424 m from every player. Raise the radius for the
-- caller's own cars and drivers (retried while the network object is still arriving).
local function keepEntity(src, netId, tries, first)
  first = first or tries
  local ent = NetworkGetEntityFromNetworkId(netId)
  if ent and ent ~= 0 and DoesEntityExist(ent) then
    local owner = NetworkGetEntityOwner(ent)
    if owner == src then
      SetEntityDistanceCullingRadius(ent, (Config.Practice.ai and Config.Practice.ai.cullRadius) or 6000.0)
      if first - tries > 2 then
        print(('[dps-roxwoodracing] practice keep: net %d kept after %.1f s'):format(netId, (first - tries) * 0.5))
      end
    else
      print(('[dps-roxwoodracing] practice keep: net %d owned by %s, not %s; culling radius left alone'):format(netId, tostring(owner), tostring(src)))
    end
    return
  end
  if tries > 0 then
    SetTimeout(500, function() keepEntity(src, netId, tries - 1, first) end)
  else
    print(('[dps-roxwoodracing] practice keep: net %d never appeared on the server (%d s), car will be culled beyond ~424 m'):format(netId, first // 2))
  end
end

RegisterNetEvent('dps-roxwoodracing:practice:keep', function(netIds)
  local src = source
  if type(netIds) ~= 'table' or #netIds > 4 then return end
  for _, netId in ipairs(netIds) do
    if type(netId) == 'number' and netId > 0 then keepEntity(src, netId, 40) end
  end
end)

lib.callback.register('dps-roxwoodracing:line:list', function(src)
  if not Staff.Can(src, 'marshal') then return nil end
  return Lines.List()
end)

CreateThread(function()
  Lines.Init()
  print(('[dps-roxwoodracing] practice lines: %d stored'):format(#Lines.List()))
end)
