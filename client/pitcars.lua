-- Static display cars in the pit area: frozen, local, no driver. Spawned when a player is
-- near, removed when they leave. /pitcar (Race Director) adds one where you are parked.
local cfg = Config.Practice and Config.Practice.pitCars or {}
local spawned, point, near = {}, nil, false

local function log(msg) print('[dps-roxwoodracing] pitcars: ' .. msg) end

local function loadModel(hash, ms)
  if not IsModelValid(hash) then return nil end
  RequestModel(hash)
  local deadline = GetGameTimer() + (ms or 5000)
  while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
  return HasModelLoaded(hash) and hash or nil
end

local function despawn()
  for _, v in ipairs(spawned) do if DoesEntityExist(v) then DeleteEntity(v) end end
  spawned = {}
end

local function spawn(rows)
  despawn()
  for _, r in ipairs(rows) do
    local hash = loadModel(joaat(r.model), 8000)
    if hash then
      RequestCollisionAtCoord(r.x, r.y, r.z)
      local veh = CreateVehicle(hash, r.x, r.y, r.z, r.h, false, false)
      SetEntityAsMissionEntity(veh, true, true)
      SetVehicleOnGroundProperly(veh)
      SetVehicleColours(veh, math.random(0, 159), math.random(0, 159))
      local liveries = GetVehicleLiveryCount(veh)
      if liveries and liveries > 0 then SetVehicleLivery(veh, math.random(0, liveries - 1)) end
      SetVehicleModKit(veh, 0)
      local modLiveries = GetNumVehicleMods(veh, 48)
      if modLiveries and modLiveries > 0 then SetVehicleMod(veh, 48, math.random(0, modLiveries - 1), false) end
      SetVehicleEngineOn(veh, false, true, true)
      SetVehicleDoorsLocked(veh, 2)
      SetVehicleDirtLevel(veh, 0.0)
      FreezeEntityPosition(veh, true)
      SetEntityLodDist(veh, cfg.lodDistance or 3000)
      SetEntityInvincible(veh, true)
      SetModelAsNoLongerNeeded(hash)
      spawned[#spawned + 1] = veh
    else
      log(('model %s failed to load, skipped'):format(tostring(r.model)))
    end
  end
  log(('%d static cars placed'):format(#spawned))
end

local function arm()
  if point then point:remove(); point = nil end
  local rows = lib.callback.await('dps-roxwoodracing:pitcar:list', false)
  if type(rows) ~= 'table' or #rows == 0 then despawn() return end
  local c, r = Practice.Extent(rows)
  point = lib.points.new({
    coords = vector3(c.x, c.y, c.z),
    distance = r + (cfg.spawnDistance or 300.0),
    onEnter = function() near = true; CreateThread(function() spawn(rows) end) end,
    onExit = function() near = false; despawn() end,
  })
  if near then CreateThread(function() spawn(rows) end) end
end

CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  Wait(2500)
  arm()
end)

RegisterNetEvent('dps-roxwoodracing:pitcar:changed', function() arm() end)
RegisterNetEvent('dps-roxwoodracing:pitcar:result', function(ok, msg)
  Notify(Config.Job.label, msg, ok and 'success' or 'error', 6000)
end)

RegisterCommand('pitcar', function(_, args)
  log(('/pitcar %s'):format(table.concat(args, ' ')))
  if not Bridge.HasJob(Config.Job.name, Config.Job.grades.director) then
    log('refused: not a Race Director on this client')
    Notify(Config.Job.label, Locale('staff_only'), 'error') return
  end
  if args[1] == 'clear' then TriggerServerEvent('dps-roxwoodracing:pitcar:clear') return end
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  local model, ent
  if veh ~= 0 then
    ent = veh
    model = GetEntityArchetypeName(veh)
    if not model or model == '' then model = nil end
  else
    ent = ped
  end
  if not model then
    local pool = cfg.models or (Config.Practice.ai and Config.Practice.ai.models) or { 'openwheel1' }
    model = pool[math.random(#pool)]
  end
  local c = GetEntityCoords(ent)
  log(('sending %s at %.1f %.1f %.1f'):format(model:lower(), c.x, c.y, c.z))
  TriggerServerEvent('dps-roxwoodracing:pitcar:add', model:lower(), c.x, c.y, c.z, GetEntityHeading(ent))
end, false)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then despawn() end
end)
