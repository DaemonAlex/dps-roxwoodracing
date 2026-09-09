-- Placed LED signs (one per track besides the Roxwood ymap sign). Each is a local frozen
-- object created when a player comes within range; the leaderboard texture replacement
-- applies to the model, so every placed sign shows this client's board.
local SIGN_MODEL = 'amir_speedway_led'
local objects, points, rows = {}, {}, {}
local function log(msg) print('[dps-roxwoodracing] signs: ' .. msg) end

local function clear()
  for _, p in ipairs(points) do p:remove() end
  for _, o in pairs(objects) do if DoesEntityExist(o) then DeleteObject(o) end end
  points, objects = {}, {}
end

local function place(row)
  local hash = joaat(SIGN_MODEL)
  if not IsModelValid(hash) then log(('model %s not valid (ytyp not loaded?)'):format(SIGN_MODEL)) return end
  RequestModel(hash)
  local deadline = GetGameTimer() + 5000
  while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
  if not HasModelLoaded(hash) then log('model did not load in 5 s') return end
  -- The stored point is where the director stood (ground level). The model's origin is not
  -- at its base, so lift it by the model's lower extent and drop it on the ground from there.
  local mn, mx = GetModelDimensions(hash)
  local stand = (Config.Leaderboard and Config.Leaderboard.signStand) or {}
  local lift = stand.height or 0.0
  -- With a stand: the stand origin sits at the director's feet and the panel origin `height`
  -- above it, the same offsets as the raceway ymap. Without one: the panel base on the ground.
  local z = stand.model and (row.z + lift) or (row.z - mn.z)
  local heading = (row.h + (stand.flip and 180.0 or 0.0)) % 360.0
  local obj = CreateObjectNoOffset(hash, row.x, row.y, z, false, false, false)
  if obj == 0 then log('object create refused') return end
  log(('sign for %s created at %.1f %.1f %.1f (model z extent %.2f..%.2f, lift %.1f, heading %.0f)'):format(row.track, row.x, row.y, z, mn.z, mx.z, lift, heading))
  SetEntityHeading(obj, heading)
  -- the stand: a vanilla prop under the panel (the raceway sign hangs off the map's own tower)
  if stand.model then
    local sh = type(stand.model) == 'number' and stand.model or joaat(stand.model)
    if IsModelValid(sh) then
      RequestModel(sh); local dl = GetGameTimer() + 5000
      while not HasModelLoaded(sh) and GetGameTimer() < dl do Wait(50) end
      if HasModelLoaded(sh) then
        local so = CreateObjectNoOffset(sh, row.x, row.y, row.z + (stand.zOffset or 0.0), false, false, false)
        if so ~= 0 then
          SetEntityHeading(so, heading); FreezeEntityPosition(so, true); SetEntityLodDist(so, 3000)
          objects[row.track .. '#stand'] = so
        end
        SetModelAsNoLongerNeeded(sh)
      end
    else log(('stand model %s not valid'):format(tostring(stand.model))) end
  end
  FreezeEntityPosition(obj, true)
  SetEntityLodDist(obj, (Config.Leaderboard and Config.Leaderboard.signLodDistance) or 3000)
  SetModelAsNoLongerNeeded(hash)
  objects[row.track] = obj
  TriggerEvent('dps-roxwoodracing:sign:nearby')      -- leaderboard re-applies the texture
end

local function arm()
  clear()
  rows = lib.callback.await('dps-roxwoodracing:sign:list', false)
  if type(rows) ~= 'table' then log('no rows from server') return end
  log(('%d sign(s) stored'):format(#rows))
  for _, row in ipairs(rows) do
    points[#points + 1] = lib.points.new({
      coords = vector3(row.x, row.y, row.z),
      distance = (Config.Leaderboard and Config.Leaderboard.signRadius) or 300.0,
      onEnter = function()
        log(('near the %s sign'):format(row.track))
        if not objects[row.track] or not DoesEntityExist(objects[row.track]) then CreateThread(function() place(row) end) end
      end,
      onExit = function()
        for _, k in ipairs({ row.track, row.track .. '#stand' }) do
          local o = objects[k]
          if o and DoesEntityExist(o) then DeleteObject(o) end
          objects[k] = nil
        end
      end,
    })
  end
end

CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  Wait(2500)
  arm()
end)

RegisterNetEvent('dps-roxwoodracing:sign:changed', function() arm() end)
RegisterNetEvent('dps-roxwoodracing:sign:result', function(ok, msg)
  Notify(Config.Job.label, msg, ok and 'success' or 'error', 7000)
end)

-- /placesign: put the sign where you stand, facing your heading, for the track you are at.
-- /placesign clear removes this track's sign.
RegisterCommand('placesign', function(_, args)
  if not Bridge.HasJob(Config.Job.name, Config.Job.grades.director) then
    Notify(Config.Job.label, Locale('staff_only'), 'error') return
  end
  local track = PracticeCurrentTrack and PracticeCurrentTrack()
  if not track then Notify(Config.Job.label, Locale('sign_no_track'), 'error') return end
  if args[1] == 'clear' then TriggerServerEvent('dps-roxwoodracing:sign:clear', track) return end
  local ped = PlayerPedId()
  local c = GetEntityCoords(ped)
  TriggerServerEvent('dps-roxwoodracing:sign:place', track, c.x, c.y, c.z, GetEntityHeading(ped))
end, false)

RegisterCommand('signstatus', function()
  local me = GetEntityCoords(PlayerPedId())
  log(('%d row(s); current track %s'):format(#rows, tostring(PracticeCurrentTrack and PracticeCurrentTrack())))
  for _, r in ipairs(rows) do
    local o = objects[r.track]
    log(('%s at %.1f %.1f %.1f: %.0f m away, object %s'):format(r.track, r.x, r.y, r.z, #(me - vector3(r.x, r.y, r.z)), (o and DoesEntityExist(o)) and 'exists' or 'none'))
  end
end, false)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then clear() end
end)
