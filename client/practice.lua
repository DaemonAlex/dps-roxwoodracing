-- AI practice cars. Local (non-networked) cars lap the recorded lines whenever no race is
-- live and this player is near the track. Each car picks a random line and carries its
-- own lane bias. GlobalState.rwPracticeAllowed is set by the server; the steering thread
-- exists only while cars are up.
local cfg = Config.Practice and Config.Practice.ai
if not cfg or not cfg.enabled then return end

local cars = {}
local running, nearTrack = false, false
local lines = nil           -- { { name, pts, closed }, ... }
local trackPoint
local startSteering

local function log(msg) print('[dps-roxwoodracing] practice: ' .. msg) end
local DRIVE_TASK = 0x93A5526E  -- SCRIPT_TASK_VEHICLE_DRIVE_TO_COORD

-- Primary/secondary colour pairs, one per grid slot (GTA colour indices)
local palette = {
  { 27, 0 },    -- race red / black
  { 64, 111 },  -- race blue / white
  { 89, 0 },    -- race yellow / black
  { 53, 111 },  -- green / white
  { 135, 0 },   -- hot pink / black
  { 111, 27 },  -- white / red
  { 38, 111 },  -- orange / white
  { 145, 0 },   -- purple / black
}

local function allowed()
  local g = GlobalState.rwPracticeAllowed
  return (g == nil or g == true) and not IsRaceActive()
end

local function loadModel(hash, ms)
  if not IsModelValid(hash) then return nil end
  RequestModel(hash)
  local deadline = GetGameTimer() + (ms or 5000)
  while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
  return HasModelLoaded(hash) and hash or nil
end

local function fetchLines()
  if lines then return lines end
  local got = lib.callback.await('dps-roxwoodracing:practice:lines', false)
  if type(got) == 'table' and #got > 0 then lines = got end
  return lines
end

local function despawn()
  running = false
  for _, c in ipairs(cars) do
    if DoesEntityExist(c.ped) then DeleteEntity(c.ped) end
    if DoesEntityExist(c.veh) then DeleteEntity(c.veh) end
  end
  cars = {}
end

local function pickModels(n)
  local pool = cfg.models
  if not pool or #pool == 0 then
    pool = {}
    for _, v in ipairs(Config.SpecFallbackVehicles or {}) do pool[#pool + 1] = v.model end
  end
  local out = {}
  for i = 1, n do out[i] = pool[math.random(#pool)] end
  return out
end

local function driveTo(c)
  local pt = c.pts[c.idx]
  local x, y, z = pt.x, pt.y, pt.z
  local off = (c.bias or 0) + (c.offset or 0)
  if off ~= 0 then x, y, z = Practice.OffsetPoint(c.pts, c.idx, c.n, off) end
  TaskVehicleDriveToCoord(c.ped, c.veh, x, y, z, c.speed or cfg.cruiseSpeed or 30.0, 0,
    GetEntityModel(c.veh), cfg.drivingStyle or 786603, cfg.stopRange or 2.0, -1)
end

local function placeOnLine(c, pt)
  SetEntityCoords(c.veh, pt.x, pt.y, pt.z + 0.5, false, false, false, false)
  SetEntityHeading(c.veh, pt.h or 0.0)
  SetVehicleOnGroundProperly(c.veh)
  SetVehicleFixed(c.veh)
  SetVehicleEngineOn(c.veh, true, true, false)
end

-- Look at the other racers (and the player's car) and set this car's pace and aim.
local function raceLogic(c, others)
  local pos = GetEntityCoords(c.veh)
  local fwd = GetEntityForwardVector(c.veh)
  local blockers = {}
  for _, o in ipairs(others) do
    if o ~= c.veh and DoesEntityExist(o) then
      local ahead, lateral = Practice.Relative(pos, fwd, GetEntityCoords(o))
      blockers[#blockers + 1] = { ahead = ahead, lateral = lateral }
    end
  end
  local speed, offset = Practice.Decide(c.cruise, blockers, cfg.aware)
  local changed = math.abs(speed - (c.speed or 0)) > 1.0 or offset ~= (c.offset or 0)
  c.speed, c.offset = speed, offset
  if changed then
    SetDriveTaskCruiseSpeed(c.ped, speed)
    driveTo(c)
  end
end

local function spawn()
  if running or not allowed() then return end
  local all = fetchLines()
  if not all then log('no line stored, nothing to run') return end
  running = true
  local count = cfg.cars or 4
  local models = pickModels(count)
  local driverHash = loadModel(joaat(cfg.driverModel or 'a_m_y_motox_01'), 5000)
  if not driverHash then log('driver model failed to load') running = false return end
  local me = GetEntityCoords(PlayerPedId())

  -- Cars are released one at a time, staggerMs apart, from a point releaseBehind points
  -- before the player on their own line, so each passes at speed and clear of the others.
  -- (Spawning far outside streaming range gives no collision and a dead drive task.)
  for i = 1, count do
    if not running then break end
    local L = all[math.random(#all)]
    local pts, n = L.pts, #L.pts
    local idx = Practice.PrevIndex(Practice.NearestIndex(pts, me), n, cfg.releaseBehind or 12)
    local pt = pts[idx]
    local hash = loadModel(joaat(models[i]), 8000)
    if hash then
      RequestCollisionAtCoord(pt.x, pt.y, pt.z)
      local veh = CreateVehicle(hash, pt.x, pt.y, pt.z + 0.5, pt.h or 0.0, false, false)
      SetEntityAsMissionEntity(veh, true, true)
      local deadline = GetGameTimer() + 3000
      while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < deadline do Wait(50) end
      SetVehicleOnGroundProperly(veh)
      -- Distinct colour per car, random livery where the model has them
      local col = palette[((i - 1) % #palette) + 1]
      SetVehicleColours(veh, col[1], col[2])
      SetVehicleExtraColours(veh, col[1], col[2])
      SetVehicleModKit(veh, 0)
      local liveries = GetVehicleLiveryCount(veh)
      if liveries and liveries > 0 then SetVehicleLivery(veh, math.random(0, liveries - 1)) end
      local modLiveries = GetNumVehicleMods(veh, 48)
      if modLiveries and modLiveries > 0 then SetVehicleMod(veh, 48, math.random(0, modLiveries - 1), false) end
      SetVehicleNumberPlateText(veh, ('PRAC %02d'):format(i))
      SetVehicleEngineOn(veh, true, true, false)
      SetVehicleCanBeVisiblyDamaged(veh, false)
      SetVehicleEngineCanDegrade(veh, false)
      local ped = CreatePedInsideVehicle(veh, 4, driverHash, -1, false, false)
      SetEntityAsMissionEntity(ped, true, true)
      SetBlockingOfNonTemporaryEvents(ped, true)
      SetPedFleeAttributes(ped, 0, false)
      SetPedCanBeDraggedOut(ped, false)
      SetDriverAbility(ped, 1.0)
      SetDriverAggressiveness(ped, cfg.aggressiveness or 0.6)
      SetDriverRacingModifier(ped, 1.0)
      SetPedKeepTask(ped, true)
      FreezeEntityPosition(veh, false)
      FreezeEntityPosition(ped, false)
      local v = cfg.paceVariance or 0.08
      local j = cfg.laneJitter or 1.5
      local c = {
        veh = veh, ped = ped, slot = i, line = L.name, pts = pts, n = n, closed = L.closed,
        lastMove = GetGameTimer(), offset = 0.0,
        bias = -j + 2 * j * math.random(),
        cruise = (cfg.cruiseSpeed or 30.0) * (1 - v + 2 * v * math.random()),
      }
      c.speed = c.cruise
      c.idx = Practice.NextIndex(idx, n, cfg.lookahead or 3)
      cars[#cars + 1] = c
      driveTo(c)
      c.lastTask = GetGameTimer()
      SetModelAsNoLongerNeeded(hash)
    else
      log(('model %s failed to load, skipped'):format(tostring(models[i])))
    end
    if i == 1 then
      log(('releasing %d cars over %d line(s), one every %d s'):format(
        count, #all, math.floor((cfg.staggerMs or 30000) / 1000)))
      startSteering()
    end
    if i < count then
      local until_ = GetGameTimer() + (cfg.staggerMs or 30000)
      while running and GetGameTimer() < until_ do Wait(250) end
    end
  end
  SetModelAsNoLongerNeeded(driverHash)
end

-- Steering: keep each car's target a few points ahead on its own line; put it back on the
-- line if stuck. Runs only while cars are up; started with the first release.
startSteering = function()
  CreateThread(function()
    while running do
      local now = GetGameTimer()
      local others = {}
      for _, c in ipairs(cars) do others[#others + 1] = c.veh end
      local mine = GetVehiclePedIsIn(PlayerPedId(), false)
      if mine ~= 0 then others[#others + 1] = mine end
      for _, c in ipairs(cars) do
        if DoesEntityExist(c.veh) and DoesEntityExist(c.ped) then
          raceLogic(c, others)
          local pos = GetEntityCoords(c.veh)
          if Practice.Dist2D(pos, c.pts[c.idx]) <= (cfg.reachRadius or 20.0) then
            local nxt, wrapped = Practice.NextIndex(c.idx, c.n, 1)
            c.idx = nxt
            if wrapped and not c.closed then placeOnLine(c, c.pts[1]); c.idx = Practice.NextIndex(1, c.n, cfg.lookahead or 3) end
            driveTo(c)
          end
          local status = GetScriptTaskStatus(c.ped, DRIVE_TASK)
          if status == 7 and now - (c.lastTask or 0) > 2000 then
            driveTo(c)
            c.lastTask = now
            c.retasks = (c.retasks or 0) + 1
          end
          if not c.logged and now - c.lastMove > 3000 then
            c.logged = true
            log(('car %d on "%s": task status %d, speed %.1f, collision %s, retasks %d'):format(
              c.slot, c.line, status, GetEntitySpeed(c.veh), tostring(HasCollisionLoadedAroundEntity(c.veh)), c.retasks or 0))
          end
          if GetEntitySpeed(c.veh) > 1.0 then
            c.lastMove = now
          elseif now - c.lastMove > (cfg.stuckMs or 8000) then
            placeOnLine(c, c.pts[c.idx])
            c.lastMove = now
            driveTo(c)
          end
        end
      end
      Wait(cfg.tickMs or 250)
    end
  end)
end

-- One point around all the lines; enter = cars up, leave = cars gone.
local function armPoint()
  if trackPoint then trackPoint:remove(); trackPoint = nil end
  local all = fetchLines()
  if not all then return false end
  local merged = {}
  for _, L in ipairs(all) do for _, p in ipairs(L.pts) do merged[#merged + 1] = p end end
  local centre, radius = Practice.Extent(merged)
  trackPoint = lib.points.new({
    coords = vector3(centre.x, centre.y, centre.z),
    distance = radius + (cfg.spawnDistance or 300.0),
    onEnter = function() nearTrack = true; CreateThread(spawn) end,
    onExit = function() nearTrack = false; despawn() end,
  })
  return true
end

CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  Wait(2000)
  if not armPoint() then log('no line stored; record one with /recordline') end
end)

AddStateBagChangeHandler('rwPracticeAllowed', 'global', function(_, _, value)
  if value == false then despawn()
  elseif nearTrack then CreateThread(spawn) end
end)

-- A newly saved line joins the pool and replaces the running set.
RegisterNetEvent('dps-roxwoodracing:line:saved', function(ok)
  if not ok then return end
  despawn()
  lines = nil
  if armPoint() and nearTrack then CreateThread(spawn) end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then despawn() end
end)
