-- AI practice cars. Local (non-networked) cars lap the recorded line whenever no race is
-- live and this player is near the track. GlobalState.rwPracticeAllowed is set by the
-- server; the steering thread exists only while cars are up.
local cfg = Config.Practice and Config.Practice.ai
if not cfg or not cfg.enabled then return end

local cars = {}
local running, nearTrack = false, false
local line, lineClosed = nil, false
local trackPoint

local function log(msg) print('[dps-roxwoodracing] practice: ' .. msg) end
local DRIVE_TASK = 0x93A5526E  -- SCRIPT_TASK_VEHICLE_DRIVE_TO_COORD

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

local function fetchLine()
  if line then return line end
  local pts, closed = lib.callback.await('dps-roxwoodracing:practice:line', false)
  if pts and #pts >= 10 then line, lineClosed = pts, closed == true end
  return line
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

local function driveTo(c, pt)
  TaskVehicleDriveToCoord(c.ped, c.veh, pt.x, pt.y, pt.z, cfg.cruiseSpeed or 30.0, 0,
    GetEntityModel(c.veh), cfg.drivingStyle or 786603, cfg.stopRange or 2.0, -1)
end

local function placeOnLine(c, pt)
  SetEntityCoords(c.veh, pt.x, pt.y, pt.z + 0.5, false, false, false, false)
  SetEntityHeading(c.veh, pt.h or 0.0)
  SetVehicleOnGroundProperly(c.veh)
  SetVehicleFixed(c.veh)
  SetVehicleEngineOn(c.veh, true, true, false)
end

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

local function spawn()
  if running or not allowed() then return end
  local pts = fetchLine()
  if not pts then log('no line stored, nothing to run') return end
  running = true
  local n = #pts
  local models = pickModels(cfg.cars or 4)
  local driverHash = loadModel(joaat(cfg.driverModel or 'a_m_y_motox_01'), 5000)
  if not driverHash then log('driver model failed to load') running = false return end

  -- Grid forms on the line nearest the player (cars far outside streaming range never
  -- get collision, and a drive task on a frozen car does nothing).
  local me = GetEntityCoords(PlayerPedId())
  local nearest = Practice.NearestIndex(pts, me)
  for i = 1, (cfg.cars or 4) do
    if not running then break end
    local idx = Practice.NextIndex(nearest, n, (i - 1) * (cfg.gridSpacing or 4))
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
      local ped = CreatePedInsideVehicle(veh, 4, driverHash, -1, false, false)
      SetEntityAsMissionEntity(ped, true, true)
      SetBlockingOfNonTemporaryEvents(ped, true)
      SetPedFleeAttributes(ped, 0, false)
      SetPedCanBeDraggedOut(ped, false)
      SetDriverAbility(ped, 1.0)
      SetDriverAggressiveness(ped, cfg.aggressiveness or 0.4)
      SetPedKeepTask(ped, true)
      FreezeEntityPosition(veh, false)
      FreezeEntityPosition(ped, false)
      local c = { veh = veh, ped = ped, idx = idx, lastMove = GetGameTimer(), slot = i }
      c.idx = Practice.NextIndex(idx, n, cfg.lookahead or 3)
      cars[#cars + 1] = c
      driveTo(c, pts[c.idx])
      c.lastTask = GetGameTimer()
      SetModelAsNoLongerNeeded(hash)
    else
      log(('model %s failed to load, skipped'):format(tostring(models[i])))
    end
    Wait(50)
  end
  SetModelAsNoLongerNeeded(driverHash)
  log(('%d cars running the "%s" line (%d points, %s)'):format(#cars, cfg.lineName or 'main', n, lineClosed and 'closed' or 'open'))

  -- Steering: keep each car's target a few points ahead; put it back on the line if stuck.
  CreateThread(function()
    while running do
      local now = GetGameTimer()
      for _, c in ipairs(cars) do
        if DoesEntityExist(c.veh) and DoesEntityExist(c.ped) then
          local pos = GetEntityCoords(c.veh)
          if Practice.Dist2D(pos, pts[c.idx]) <= (cfg.reachRadius or 20.0) then
            local nxt, wrapped = Practice.NextIndex(c.idx, n, 1)
            c.idx = nxt
            if wrapped and not lineClosed then placeOnLine(c, pts[1]); c.idx = Practice.NextIndex(1, n, cfg.lookahead or 3) end
            driveTo(c, pts[c.idx])
          end
          local status = GetScriptTaskStatus(c.ped, DRIVE_TASK)
          if status == 7 and now - (c.lastTask or 0) > 2000 then
            driveTo(c, pts[c.idx])
            c.lastTask = now
            c.retasks = (c.retasks or 0) + 1
          end
          if not c.logged and now - c.lastMove > 3000 then
            c.logged = true
            log(('car %d: task status %d, speed %.1f, collision %s, retasks %d'):format(
              c.slot, status, GetEntitySpeed(c.veh), tostring(HasCollisionLoadedAroundEntity(c.veh)), c.retasks or 0))
          end
          if GetEntitySpeed(c.veh) > 1.0 then
            c.lastMove = now
          elseif now - c.lastMove > (cfg.stuckMs or 8000) then
            placeOnLine(c, pts[c.idx])
            c.lastMove = now
            driveTo(c, pts[c.idx])
          end
        end
      end
      Wait(cfg.tickMs or 250)
    end
  end)
end

-- One point around the whole line; enter = cars up, leave = cars gone.
CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  Wait(2000)
  local pts = fetchLine()
  if not pts then log('no line stored; record one with /recordline') return end
  local centre, radius = Practice.Extent(pts)
  trackPoint = lib.points.new({
    coords = vector3(centre.x, centre.y, centre.z),
    distance = radius + (cfg.spawnDistance or 300.0),
    onEnter = function() nearTrack = true; CreateThread(spawn) end,
    onExit = function() nearTrack = false; despawn() end,
  })
end)

AddStateBagChangeHandler('rwPracticeAllowed', 'global', function(_, _, value)
  if value == false then despawn()
  elseif nearTrack then CreateThread(spawn) end
end)

-- A newly saved line replaces the running one.
RegisterNetEvent('dps-roxwoodracing:line:saved', function(ok, _, name)
  if not ok or name ~= (cfg.lineName or 'main') then return end
  despawn()
  line = nil
  if trackPoint then trackPoint:remove(); trackPoint = nil end
  local pts = fetchLine()
  if not pts then return end
  local centre, radius = Practice.Extent(pts)
  trackPoint = lib.points.new({
    coords = vector3(centre.x, centre.y, centre.z),
    distance = radius + (cfg.spawnDistance or 300.0),
    onEnter = function() nearTrack = true; CreateThread(spawn) end,
    onExit = function() nearTrack = false; despawn() end,
  })
  if nearTrack then CreateThread(spawn) end
end)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then despawn() end
end)
