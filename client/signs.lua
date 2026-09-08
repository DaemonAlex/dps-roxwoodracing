-- Placed LED signs (one per track besides the Roxwood ymap sign). Each is a local frozen
-- object created when a player comes within range; the leaderboard texture replacement
-- applies to the model, so every placed sign shows this client's board.
local SIGN_MODEL = 'amir_speedway_led'
local objects, points = {}, {}

local function clear()
  for _, p in ipairs(points) do p:remove() end
  for _, o in pairs(objects) do if DoesEntityExist(o) then DeleteObject(o) end end
  points, objects = {}, {}
end

local function place(row)
  local hash = joaat(SIGN_MODEL)
  if not IsModelValid(hash) then return end
  RequestModel(hash)
  local deadline = GetGameTimer() + 5000
  while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
  if not HasModelLoaded(hash) then return end
  local obj = CreateObjectNoOffset(hash, row.x, row.y, row.z, false, false, false)
  if obj == 0 then return end
  SetEntityHeading(obj, row.h)
  FreezeEntityPosition(obj, true)
  SetEntityLodDist(obj, (Config.Leaderboard and Config.Leaderboard.signLodDistance) or 3000)
  SetModelAsNoLongerNeeded(hash)
  objects[row.track] = obj
  TriggerEvent('dps-roxwoodracing:sign:nearby')      -- leaderboard re-applies the texture
end

local function arm()
  clear()
  local rows = lib.callback.await('dps-roxwoodracing:sign:list', false)
  if type(rows) ~= 'table' then return end
  for _, row in ipairs(rows) do
    points[#points + 1] = lib.points.new({
      coords = vector3(row.x, row.y, row.z),
      distance = (Config.Leaderboard and Config.Leaderboard.signRadius) or 300.0,
      onEnter = function()
        if not objects[row.track] or not DoesEntityExist(objects[row.track]) then CreateThread(function() place(row) end) end
      end,
      onExit = function()
        local o = objects[row.track]
        if o and DoesEntityExist(o) then DeleteObject(o) end
        objects[row.track] = nil
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

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then clear() end
end)
