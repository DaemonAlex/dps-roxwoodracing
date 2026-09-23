-- AI practice cars and practice mode. One server-elected host client spawns and drives
-- the shared (networked) grid; every client near the track runs the lap clock and sees the
-- same cars. The AI reacts to every player, and its pace follows the best rolling average
-- among players on the track. GlobalState.rwPracticeAllowed is set by the server; the
-- steering thread exists only while cars are up.
local cfg = Config.Practice and Config.Practice.ai
if not cfg or not cfg.enabled then return end
local mode = Config.Practice.mode or {}

local cars = {}
local running, nearTrack, isHost = false, false, false
local lines = nil           -- { { name, pts, closed }, ... }
local trackPoint, startZone
local startSteering
local targetLap = nil                         -- best rolling average on the track (ms), from the server
local paceMult = mode.defaultPace or 0.85     -- grid pace multiplier
local players = {}                            -- host only: pid -> { prog, laps }
local clockStart, lastClockAt = nil, 0

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
  local bend = Practice.BendAhead(c.pts, c.prog, c.n, cfg.aware.bendLookahead or 6, c.closed)
  local speed, offset = Practice.Decide(c.cruise, blockers, cfg.aware, { bend = bend })
  local retask = offset ~= (c.offset or 0)          -- a new aim point needs a new task
  local respeed = math.abs(speed - (c.speed or 0)) > 1.0
  c.speed, c.offset = speed, offset
  if retask then driveTo(c)                         -- driveTo carries the speed too
  elseif respeed then SetDriveTaskCruiseSpeed(c.ped, speed) end   -- adjust the running task, no restart
end

local function spawn()
  if running or not allowed() or not isHost then return end
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
      local net = cfg.networked ~= false
      local veh = CreateVehicle(hash, pt.x, pt.y, pt.z + 0.5, pt.h or 0.0, net, false)
      if veh == 0 then
        -- The game refused the spawn (unloaded area or something in the way): one retry a
        -- point further on, after a short wait.
        log(('car %d: spawn refused at %.1f %.1f %.1f, retrying'):format(i, pt.x, pt.y, pt.z))
        Wait(500)
        idx = Practice.NextIndex(idx, n, 1); pt = pts[idx]
        RequestCollisionAtCoord(pt.x, pt.y, pt.z)
        veh = CreateVehicle(hash, pt.x, pt.y, pt.z + 0.5, pt.h or 0.0, net, false)
      end
      if veh == 0 then
        log(('car %d: spawn refused twice, skipped'):format(i))
        SetModelAsNoLongerNeeded(hash)
        goto continue
      end
      SetEntityAsMissionEntity(veh, true, true)
      if net then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        SetNetworkIdCanMigrate(netId, false)
        SetNetworkIdExistsOnAllMachines(netId, true)
      end
      SetEntityLoadCollisionFlag(veh, true)
      local deadline = GetGameTimer() + 3000
      while not HasCollisionLoadedAroundEntity(veh) and GetGameTimer() < deadline do Wait(50) end
      local vc = GetEntityCoords(veh)
      log(('car %d: vehicle at %.1f %.1f %.1f (asked %.1f %.1f %.1f), collision %s, %.0f m from player'):format(
        i, vc.x, vc.y, vc.z, pt.x, pt.y, pt.z, tostring(HasCollisionLoadedAroundEntity(veh)), #(vc - GetEntityCoords(PlayerPedId()))))
      -- Driver first, before any mods or tuning touch the vehicle.
      local ped = CreatePedInsideVehicle(veh, 4, driverHash, -1, net, false)
      if ped == 0 then
        log(('car %d: in-vehicle driver create refused (model loaded=%s), creating beside and seating'):format(i, tostring(HasModelLoaded(driverHash))))
        ped = CreatePed(4, driverHash, pt.x, pt.y, pt.z + 1.0, pt.h or 0.0, net, false)
        if ped == 0 then
          log(('car %d: networked ped create refused too, trying a local ped'):format(i))
          ped = CreatePed(4, driverHash, pt.x, pt.y, pt.z + 1.0, pt.h or 0.0, false, false)
        end
        if ped ~= 0 then
          SetEntityLoadCollisionFlag(ped, true)
          local seatDeadline = GetGameTimer() + 2000
          SetPedIntoVehicle(ped, veh, -1)
          while GetVehiclePedIsIn(ped, false) ~= veh and GetGameTimer() < seatDeadline do Wait(50); SetPedIntoVehicle(ped, veh, -1) end
        end
      end
      if ped == 0 or GetVehiclePedIsIn(ped, false) ~= veh then
        log(('car %d: no driver could be seated, car removed'):format(i))
        if ped ~= 0 and DoesEntityExist(ped) then DeleteEntity(ped) end
        DeleteEntity(veh)
        SetModelAsNoLongerNeeded(hash)
        goto continue
      end
      SetEntityAsMissionEntity(ped, true, true)
      local vehNet, pedNet = 0, 0
      if net then
        -- The network ids exist only once the objects are registered; wait for them before
        -- asking the server to keep the pair beyond the OneSync culling distance.
        local netDeadline = GetGameTimer() + 5000
        while (vehNet == 0 or pedNet == 0) and GetGameTimer() < netDeadline do
          vehNet = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or 0
          pedNet = NetworkGetEntityIsNetworked(ped) and NetworkGetNetworkIdFromEntity(ped) or 0
          if vehNet == 0 or pedNet == 0 then Wait(100) end
        end
        if pedNet ~= 0 then SetNetworkIdCanMigrate(pedNet, false) end
        if vehNet ~= 0 and pedNet ~= 0 then
          TriggerServerEvent('dps-roxwoodracing:practice:keep', { vehNet, pedNet })
        else
          log(('car %d: no network id after 5 s (veh %d, ped %d); it will be culled beyond ~424 m'):format(i, vehNet, pedNet))
        end
      end
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
      if cfg.tunePreset and Customs and Customs.ApplyTune then Customs.ApplyTune(veh, cfg.tunePreset) end
      if (cfg.topSpeedBoost or 0) > 0 then ModifyVehicleTopSpeed(veh, cfg.topSpeedBoost) end
      if cfg.engineSounds and #cfg.engineSounds > 0 then
        ForceVehicleEngineAudio(veh, cfg.engineSounds[math.random(#cfg.engineSounds)])
      end
      SetAudioVehiclePriority(veh, cfg.audioPriority or 3)
      SetVehicleEngineOn(veh, true, true, true)
      SetVehicleCanBeVisiblyDamaged(veh, false)
      SetVehicleEngineCanDegrade(veh, false)
      SetBlockingOfNonTemporaryEvents(ped, true)
      SetPedFleeAttributes(ped, 0, false)
      SetPedCanBeDraggedOut(ped, false)
      SetDriverAbility(ped, 1.0)
      SetDriverAggressiveness(ped, cfg.aggressiveness or 0.6)
      SetDriverRacingModifier(ped, 1.0)
      SetPedKeepTask(ped, true)
      GivePedHelmet(ped, true, 4096, -1)
      SetPedHelmet(ped, true)
      FreezeEntityPosition(veh, false)
      FreezeEntityPosition(ped, false)
      -- Keep simulating far from the player: without loaded collision an entity is frozen,
      -- and the tower looks over most of the lap.
      SetEntityLoadCollisionFlag(ped, true)
      SetEntityLodDist(veh, cfg.lodDistance or 3000)
      SetEntityLodDist(ped, cfg.lodDistance or 3000)
      local v = cfg.paceVariance or 0.08
      local j = cfg.laneJitter or 1.5
      local c = {
        veh = veh, ped = ped, vehNet = vehNet, pedNet = pedNet, slot = i, line = L.name, pts = pts, n = n, closed = L.closed,
        lastMove = GetGameTimer(), offset = 0.0,
        bias = -j + 2 * j * math.random(),
        pace = 1 - v + 2 * v * math.random(),
      }
      c.cruise = (pts[idx].v or cfg.cruiseSpeed or 30.0) * c.pace
      c.speed = c.cruise
      c.prog = idx
      c.lastProg = GetGameTimer()
      c.laps = 0
      c.driver = (cfg.driverNames and cfg.driverNames[((i - 1) % #cfg.driverNames) + 1]) or ('CAR' .. i)
      c.idx = Practice.NextIndex(idx, n, Practice.AimByCurvature(pts, idx, n, cfg.aimCornerPts or 2, cfg.aimMinPts or 4, cfg.aimMaxTurnDeg or 15, L.closed))
      cars[#cars + 1] = c
      driveTo(c)
      c.lastTask = GetGameTimer()
      if (cfg.releaseSpeed or 0) > 0 then SetVehicleForwardSpeed(veh, cfg.releaseSpeed) end
      SetModelAsNoLongerNeeded(hash)
    else
      log(('model %s failed to load, skipped'):format(tostring(models[i])))
    end
    ::continue::
    if i == 1 then
      log(('releasing %d cars over %d line(s), one every %d s; first line "%s" %d points closed=%s'):format(
        count, #all, math.floor((cfg.staggerMs or 30000) / 1000), tostring(all[1].name), #all[1].pts, tostring(all[1].closed)))
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
    local lastBoard = 0
    while running do
      local now = GetGameTimer()
      local others = {}
      for _, c in ipairs(cars) do others[#others + 1] = c.veh end
      for _, pid in ipairs(GetActivePlayers()) do
        local pv = GetVehiclePedIsIn(GetPlayerPed(pid), false)
        if pv ~= 0 then others[#others + 1] = pv end
      end
      for _, c in ipairs(cars) do
        if not DoesEntityExist(c.veh) and (c.vehNet or 0) ~= 0 and NetworkDoesNetworkIdExist(c.vehNet) then
          -- The local handle died (culled and re-sent by the server); pick the car back up by id.
          c.veh = NetToVeh(c.vehNet)
          if (c.pedNet or 0) ~= 0 and NetworkDoesNetworkIdExist(c.pedNet) then c.ped = NetToPed(c.pedNet) end
          if DoesEntityExist(c.veh) and DoesEntityExist(c.ped) then
            log(('car %d: re-bound to net %d after a culling round trip'):format(c.slot, c.vehNet))
            driveTo(c); c.lastTask = now
            TriggerServerEvent('dps-roxwoodracing:practice:keep', { c.vehNet, c.pedNet })
          end
        end
        if DoesEntityExist(c.veh) and DoesEntityExist(c.ped) then
          if (c.vehNet or 0) ~= 0 and now - (c.lastKeep or 0) > 30000 then
            c.lastKeep = now
            TriggerServerEvent('dps-roxwoodracing:practice:keep', { c.vehNet, c.pedNet })
          end
          local pos = GetEntityCoords(c.veh)
          -- Progress: the nearest of the next few points (never backwards), so a wobble or
          -- the loop seam cannot pin the tracker behind the car.
          local bestI, bestD = c.prog, Practice.Dist2D(pos, c.pts[c.prog])
          local i = c.prog
          for _ = 1, 6 do
            local nxt, wrapped = Practice.NextIndex(i, c.n, 1)
            if wrapped and not c.closed then
              placeOnLine(c, c.pts[1]); c.prog = 1; c.idx = Practice.NextIndex(1, c.n, cfg.aimMinPts or 4); driveTo(c)
              bestI = 1; break
            end
            i = nxt
            local di = Practice.Dist2D(pos, c.pts[i])
            if di < bestD then bestI, bestD = i, di end
          end
          if bestI ~= c.prog then
            if bestI < c.prog then                                   -- crossed the seam
              c.laps = (c.laps or 0) + 1
              if c.lapStart then
                c.lastLapMs = now - c.lapStart
                -- Re-fit the grid pace to the best player average on the track
                local m = Practice.PaceMult(c.lastLapMs, c.lapMult or paceMult, targetLap, mode.margin, mode.minPace, mode.maxPace)
                if m then paceMult = m end
              end
              c.lapStart, c.lapMult = now, paceMult
            end
            c.prog = bestI; c.lastProg = now
          end
          -- pace for this stretch of line: its speed profile x this car's pace factor x grid pace
          c.cruise = (c.pts[c.prog].v or cfg.cruiseSpeed or 30.0) * c.pace * paceMult
          raceLogic(c, others)
          -- Aim point scales with speed so the car never overshoots its own target.
          local aim = Practice.AimPoints(GetEntitySpeed(c.veh), cfg.aimSeconds or 2.0, Config.Practice.recordSpacing or 12.0,
            cfg.aimMinPts or 4, cfg.aimMaxPts or 14)
          -- ...but never past a bend: a straight aim through a corner ends in the wall.
          local curv = Practice.AimByCurvature(c.pts, c.prog, c.n, cfg.aimCornerPts or 2, cfg.aimMaxPts or 14, cfg.aimMaxTurnDeg or 25, c.closed)
          if curv < aim then aim = curv end
          -- ...and never cut the corner: the chord from the car to the aim stays near the line.
          local chord = Practice.AimByChord(c.pts, pos, c.prog, c.n, cfg.aimCornerPts or 2, aim, cfg.aimMaxCut or 1.5, c.closed)
          if chord < aim then aim = chord end
          local want = Practice.NextIndex(c.prog, c.n, aim)
          if Practice.Forward(c.idx, want, c.n) >= (cfg.retargetStep or 2) then
            c.idx = want
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
          end
          local noProgress = now - (c.lastProg or c.lastMove) > (cfg.noProgressMs or 10000)
          if now - c.lastMove > (cfg.stuckMs or 6000) or noProgress then
            -- Stuck: back onto the line at the car's own progress point. Stuck again within
            -- a few points of the same place: skip well past it so it stops re-running the wall.
            local at = c.prog
            if c.stuckAt and Practice.Forward(c.stuckAt, c.prog, c.n) <= 4 then
              at = Practice.NextIndex(c.prog, c.n, cfg.stuckSkipPts or 8)
              log(('car %d stuck twice near point %d, skipping to %d'):format(c.slot, c.prog, at))
            end
            c.stuckAt = c.prog
            c.stuckCount = (c.stuckCount or 0) + 1
            c.prog = at
            c.lastProg = now
            c.idx = Practice.NextIndex(at, c.n, cfg.aimCornerPts or 2)
            placeOnLine(c, c.pts[at])
            c.lastMove = now
            driveTo(c)
          end
        end
      end
      -- Players on the track: progress on the main line and laps at the seam (host only)
      local main = lines and lines[1]
      if main then
        local n = #main.pts
        local seen = {}
        for _, pid in ipairs(GetActivePlayers()) do
          local pv = GetVehiclePedIsIn(GetPlayerPed(pid), false)
          if pv ~= 0 then
            local pos = GetEntityCoords(pv)
            local idx = Practice.NearestIndex(main.pts, pos)
            if Practice.Dist2D(pos, main.pts[idx]) <= 30.0 then
              local rec = players[pid] or { laps = 0, prog = idx }
              if rec.prog > n * 0.9 and idx < n * 0.1 then rec.laps = rec.laps + 1 end
              rec.prog = idx
              rec.name = Practice.ShortName(GetPlayerName(pid))
              players[pid] = rec
              seen[pid] = true
            end
          end
        end
        for pid in pairs(players) do if not seen[pid] then players[pid] = nil end end
      end
      -- Running order (AI + players) to everyone's sign via the server
      if now - lastBoard >= (cfg.boardEveryMs or 1000) then
        lastBoard = now
        local order = {}
        for _, c in ipairs(cars) do if DoesEntityExist(c.veh) then order[#order + 1] = { laps = c.laps or 0, prog = c.prog, name = c.driver } end end
        for _, rec in pairs(players) do order[#order + 1] = rec end
        table.sort(order, function(a, b)
          if (a.laps or 0) ~= (b.laps or 0) then return (a.laps or 0) > (b.laps or 0) end
          return a.prog > b.prog
        end)
        local names = {}
        for i = 1, math.min(9, #order) do names[i] = order[i].name end
        TriggerServerEvent('dps-roxwoodracing:practice:board', cfg.boardTitle or 'PRAC', names)
      end
      Wait(cfg.tickMs or 250)
    end
    TriggerEvent('dps-roxwoodracing:practice:boardOff')
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
    onEnter = function()
      nearTrack = true
      TriggerServerEvent('dps-roxwoodracing:practice:enter')
      CreateThread(spawn)
    end,
    onExit = function()
      nearTrack = false
      clockStart = nil
      TriggerServerEvent('dps-roxwoodracing:practice:leave')
      despawn()
    end,
  })
  -- Start line: the first point of the main line. Crossing it starts the lap clock;
  -- the next crossing completes the lap.
  if startZone then startZone:remove(); startZone = nil end
  local s0 = all[1].pts[1]
  startZone = lib.zones.sphere({
    coords = vector3(s0.x, s0.y, s0.z),
    radius = mode.startRadius or 15.0,
    onEnter = function()
      if IsRaceActive() or not allowed() then return end
      if GetVehiclePedIsIn(PlayerPedId(), false) == 0 then return end
      local now = GetGameTimer()
      if now - lastClockAt < 10000 then return end
      lastClockAt = now
      if clockStart then
        local ms = now - clockStart
        clockStart = now
        TriggerServerEvent('dps-roxwoodracing:practice:lap', ms)
      else
        clockStart = now
        Notify(Config.Job.label, Locale('practice_clock_started'), 'inform', 5000)
      end
    end,
  })
  return true
end

CreateThread(function()
  while not NetworkIsSessionStarted() do Wait(500) end
  Wait(2000)
  if not armPoint() then log('no line stored; record one with /recordline') end
end)

AddStateBagChangeHandler('rwPracticeAllowed', 'global', function(_, _, value)
  if value == false then despawn(); clockStart = nil
  elseif nearTrack then CreateThread(spawn) end
end)

-- Server-elected host: only the host spawns and drives the grid
RegisterNetEvent('dps-roxwoodracing:practice:host', function(on)
  isHost = on == true
  log(('host=%s'):format(tostring(isHost)))
  if isHost then
    if nearTrack then CreateThread(spawn) end
  else
    despawn()
  end
end)

RegisterNetEvent('dps-roxwoodracing:practice:target', function(ms)
  targetLap = ms
  if not ms then paceMult = mode.defaultPace or 0.85 end
end)

RegisterNetEvent('dps-roxwoodracing:practice:lapResult', function(ms, best, isBest, avg, laps)
  Notify(Config.Job.label, Locale(isBest and 'practice_lap_best' or 'practice_lap', Practice.FormatMs(ms)), isBest and 'success' or 'inform', 7000)
  Notify(Config.Job.label, Locale('practice_lap_detail', Practice.FormatMs(best), math.min(laps, mode.keepLaps or 5), Practice.FormatMs(avg)), 'inform', 7000)
end)

RegisterNetEvent('dps-roxwoodracing:practice:raceForming', function(lobbyName)
  Notify(Config.Job.label, Locale('practice_forming', lobbyName), 'warning', 12000)
end)

RegisterNetEvent('dps-roxwoodracing:practice:cleared', function()
  clockStart = nil
  Notify(Config.Job.label, Locale('practice_cleared'), 'warning', 8000)
end)

-- A newly saved line joins the pool and replaces the running set.
RegisterNetEvent('dps-roxwoodracing:line:saved', function(ok)
  if not ok then return end
  despawn()
  lines = nil
  if armPoint() and nearTrack then CreateThread(spawn) end
end)

-- /practicestatus: one F8 line per car (where it is, how fast, laps, stuck resets)
RegisterCommand('practicestatus', function()
  log(('running=%s nearTrack=%s host=%s cars=%d allowed=%s pace=%.2f target=%s clock=%s'):format(
    tostring(running), tostring(nearTrack), tostring(isHost), #cars, tostring(allowed()), paceMult,
    targetLap and Practice.FormatMs(targetLap) or 'none', clockStart and Practice.FormatMs(GetGameTimer() - clockStart) or 'off'))
  for pid, rec in pairs(players) do log(('player %s: lap %d, point %d'):format(rec.name or pid, rec.laps or 0, rec.prog or 0)) end
  local me = GetEntityCoords(PlayerPedId())
  for _, c in ipairs(cars) do
    if DoesEntityExist(c.veh) then
      local pos = GetEntityCoords(c.veh)
      log(('car %d %s on "%s": %.0f m away, %.0f km/h, lap %d, point %d/%d, target v %.0f, driver in car=%s, stuck resets=%d'):format(
        c.slot, c.driver or '?', c.line or '?', #(pos - me), GetEntitySpeed(c.veh) * 3.6, c.laps or 0, c.prog or 0, c.n or 0,
        (c.speed or 0) * 3.6, tostring(DoesEntityExist(c.ped) and GetVehiclePedIsIn(c.ped, false) == c.veh), c.stuckCount or 0))
    else
      log(('car %d %s: vehicle handle gone; net %s %s'):format(c.slot, c.driver or '?', tostring(c.vehNet),
        (c.vehNet or 0) ~= 0 and (NetworkDoesNetworkIdExist(c.vehNet) and 'still exists on the network (will re-bind)' or 'gone from the network too') or 'was never networked'))
    end
  end
end, false)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then despawn() end
end)
