-- s_main.lua

-- Config is a shared global
-- Bridge (loaded before this file via fxmanifest) provides: Bridge.Framework,
-- Bridge.GetPlayerIdentifier(), Bridge.AddMoney(), etc.

--------------------------------------------------------------------------------
-- server-side notification helper (routes through client Notify)
--------------------------------------------------------------------------------
local function ServerNotify(target, title, description, ntype, duration)
  TriggerClientEvent('dps-roxwoodracing:client:notify', target, title, description, ntype, duration)
end

--------------------------------------------------------------------------------
-- re-add table helpers from s_function.lua
--------------------------------------------------------------------------------
local function table_contains(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then return true end
  end
  return false
end

local function table_count(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

--------------------------------------------------------------------------------
-- Precomputed lookup tables from Config (built once at load)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Per-player event rate limiter (simple timestamp bucket)
--------------------------------------------------------------------------------
local _rlBuckets = {}
local function RateLimit(src, event, ms)
  local key = src .. event
  local now = GetGameTimer()
  if _rlBuckets[key] and (now - _rlBuckets[key]) < (ms or 500) then return true end
  _rlBuckets[key] = now
  return false
end

-- Refund cooldown tracker: prevents join-refund-rejoin cycling
local _refundCD = {} -- [src] = timestamp

-- Periodic cleanup of stale rate-limit / refund entries (every 5 min)
CreateThread(function()
  while true do
    Wait(300000)
    local now = GetGameTimer()
    for k, t in pairs(_rlBuckets) do if now - t > 60000 then _rlBuckets[k] = nil end end
    for k, t in pairs(_refundCD) do if now - t > 120000 then _refundCD[k] = nil end end
  end
end)

--------------------------------------------------------------------------------
-- lobby storage
--------------------------------------------------------------------------------
local lobbies        = {}    -- [lobbyName] = { owner, track, laps, players, ... }
local pendingChoices = {}    -- for vehicle selection
local amirState      = {}    -- per-lobby AMIR throttle and last state

-- Multi-lobby coordination state:
--  gridLocked   — held while a lobby is spawning vehicles on the shared start line,
--                 so a second lobby starting at the same instant waits until the
--                 first race's cars have cleared the grid.
--  primaryLobby — the only lobby that can drive the physical AMIR LED scoreboard.
--                 First started lobby gets it; when that lobby ends, we promote
--                 the next running lobby.
local gridLocked   = false
local primaryLobby = nil

-- Helper: find lobby by player id
local function findLobbyByPlayer(pid)
  for name, lob in pairs(lobbies) do
    for _, p in ipairs(lob.players or {}) do
      if p == pid then return name, lob end
    end
  end
  return nil, nil
end

-- Helper: build the payload sent to clients in dps-roxwoodracing:updateLobbyInfo.
-- Resolves names via the framework bridge so RP servers see character names
-- (e.g. "John Smith") instead of Steam display names.
local function buildLobbyInfo(lobbyName, lob)
  local names = {}
  for i, pid in ipairs(lob.players or {}) do
    names[i] = Bridge.GetPlayerName(pid)
  end
  return {
    name     = lobbyName,
    hostName = Bridge.GetPlayerName(lob.owner),
    track    = lob.track,
    players  = lob.players,
    owner    = lob.owner,
    laps     = lob.laps,
    names    = names,
    mode     = lob.mode,
    class    = lob.class,
    tune     = lob.tune,
  }
end


-- Server-side check of an Open-mode car: the netId must resolve to a vehicle whose plate matches,
-- with the requesting player in the driver seat. Class cannot be read server-side; the registry
-- category is used when the model is known, otherwise the client-reported class is accepted.
local function VerifyOpenVehicle(src, vehicle, classKey)
  if type(vehicle) ~= 'table' or type(vehicle.plate) ~= 'string' then return false, 'open_need_vehicle' end
  local netId = tonumber(vehicle.netId)
  if not netId then return false, 'open_need_vehicle' end
  local veh = NetworkGetEntityFromNetworkId(netId)
  if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return false, 'open_need_vehicle' end
  local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local claimed = vehicle.plate:gsub('^%s+', ''):gsub('%s+$', '')
  if plate == '' or plate ~= claimed then return false, 'open_not_owner' end
  if GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return false, 'open_need_vehicle' end
  if not Lobbies.VerifyOwnedVehicle(src, plate) then return false, 'open_not_owner' end
  local classId = Lobbies.ClassForModel(GetEntityModel(veh)) or tonumber(vehicle.class)
  if not Lobbies.OpenClassAllows(classKey, classId) then return false, 'open_wrong_class' end
  return true, nil, { netId = netId, plate = plate }
end

local function VehicleAlreadyRegistered(lob, plate, exceptPid)
  for pid, v in pairs(lob.vehicles or {}) do
    if pid ~= exceptPid and v.plate == plate then return true end
  end
  return false
end

local function DeleteSpawnedVehicle(lob, pid)
  local veh = lob.spawned and lob.spawned[pid]
  if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
  if lob.spawned then lob.spawned[pid] = nil end
end

-- Refund exactly what this player paid into this lobby (recorded receipt), and take it out of the pool.
local function RefundLobbyFee(lob, lobbyName, pid)
  local receipt = lob.fees and lob.fees[pid]
  if not receipt then return end
  lob.fees[pid] = nil
  lob.prizePool = math.max(0, (lob.prizePool or 0) - (receipt.amount or 0))
  Rewards.RefundEntryFee(pid, lobbyName, receipt)
end

-- AI practice cars may run only while no race is live (clients read the global state).
local function SyncPracticeState()
  local live, inLobby = false, {}
  for _, l in pairs(lobbies) do
    if l.raceLive then
      live = true
      for _, pid in ipairs(l.players) do inLobby[pid] = true end
    end
  end
  local wasAllowed = GlobalState.rwPracticeAllowed
  GlobalState.rwPracticeAllowed = not live
  if live and wasAllowed ~= false and PracticeServer and PracticeServer.ClearTrack then
    PracticeServer.ClearTrack(inLobby)   -- race just went live: practice cars off the track
  end
end
GlobalState.rwPracticeAllowed = true

local function PromoteSign(lobbyName)
  if primaryLobby ~= lobbyName then return end
  primaryLobby = nil
  for n, l in pairs(lobbies) do if l.isStarted then primaryLobby = n break end end
  if Config.Leaderboard and Config.Leaderboard.enabled and not primaryLobby then exports['dps-roxwoodracing']:ShowIdleLeaderboard() end
end

local FinishRaceIfDone -- defined with lapPassed below

Race = Race or {}

function Race.IsPlayerInLobby(pid)
  local name = findLobbyByPlayer(pid)
  return name ~= nil
end

function Race.ListLobbies()
  local out = {}
  for name, lob in pairs(lobbies) do out[#out+1] = { name = name, track = lob.track, mode = lob.mode, started = lob.isStarted, players = #lob.players } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Race.SetSignMode(lobbyName, mode)
  if mode ~= 'names' and mode ~= 'toggle' then return end
  lobbyName = lobbyName or primaryLobby
  if not lobbyName or not lobbies[lobbyName] then return end
  amirState[lobbyName] = amirState[lobbyName] or { last = 0, lastSwitch = 0, showNames = true }
  amirState[lobbyName].vm = mode; amirState[lobbyName].last = 0; amirState[lobbyName].lastSwitch = 0; amirState[lobbyName].showNames = true
end

function Race.EndLobby(lobbyName, reason)
  local lob = lobbies[lobbyName]
  if not lob then return end
  for _, pid in ipairs(lob.players) do
    if not lob.raceLive then RefundLobbyFee(lob, lobbyName, pid) end
    TriggerClientEvent('dps-roxwoodracing:kickedFromLobby', pid, lobbyName, reason or 'ended')
    TriggerClientEvent('dps-roxwoodracing:client:destroyprops', pid)
    TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', pid, nil)
    if lob.raceLive then TriggerClientEvent('dps-roxwoodracing:client:finishTeleport', pid, Config.outCoords, lob.mode == 'open') end
    DeleteSpawnedVehicle(lob, pid)
  end
  pendingChoices[lobbyName] = nil
  amirState[lobbyName] = nil
  lobbies[lobbyName] = nil
  SyncPracticeState()
  TriggerClientEvent('dps-roxwoodracing:setLobbyState', -1, next(lobbies) ~= nil)
  PromoteSign(lobbyName)
end

math.randomseed(GetGameTimer())

--------------------------------------------------------------------------------
-- callbacks for client queries
--------------------------------------------------------------------------------
lib.callback.register("dps-roxwoodracing:getLobbies", function(source)
  local result = {}
  for name, lobby in pairs(lobbies) do
    table.insert(result, {
      label = Locale("lobby_label_template", name, lobby.track, #lobby.players) .. (lobby.mode == 'open' and ' [Open]' or ' [Spec]'),
      value = name,
      mode  = lobby.mode,
    })
  end
  return result
end)

lib.callback.register("dps-roxwoodracing:getLobbyPlayers", function(source, lobbyName)
  local lobby = lobbies[lobbyName]
  return lobby and lobby.players or {}
end)

--------------------------------------------------------------------------------
-- CREATE LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:createLobby", function(args)
  local src = source
  if RateLimit(src, "createLobby", 2000) then return end
  local ok, errKey, c = Validate.CreateArgs(args, Config)
  if not ok then ServerNotify(src, Config.Job.label, Locale(errKey), 'error') return end
  for _, existing in pairs(lobbies) do
    if existing.track == c.track then ServerNotify(src, Config.Job.label, Locale("track_in_use"), 'error') return end
  end
  if lobbies[c.name] then ServerNotify(src, Config.Job.label, Locale("lobby_exists"), 'error') return end
  local openVeh
  if c.mode == 'open' then
    local okv, err, v = VerifyOpenVehicle(src, args.vehicle, c.class)
    if not okv then ServerNotify(src, Config.Job.label, Locale(err, Config.OpenClasses[c.class].label), 'error') return end
    openVeh = v
  end
  local paid, receipt = Rewards.ChargeEntryFee(src, c.name)
  if not paid then return end
  lobbies[c.name] = {
    name = c.name, owner = src, track = c.track, laps = c.laps, mode = c.mode, class = c.class, tune = c.tune,
    players = { src }, vehicles = {}, checkpointProgress = {}, isStarted = false, lapProgress = {}, finished = {},
    lapTimes = {}, startTime = {}, progress = {}, prizePool = 0, spawned = {}, fees = {}, raceLive = false,
  }
  if openVeh then lobbies[c.name].vehicles[src] = openVeh end
  lobbies[c.name].fees[src] = receipt
  lobbies[c.name].prizePool = receipt and receipt.amount or 0
  if Config.DebugPrints then print("[DEBUG] Lobby created: " .. c.name .. " mode=" .. c.mode) end
  ServerNotify(src, Config.Job.label, Locale("lobby_created", c.name), 'success')
  if PracticeServer and PracticeServer.RaceForming then PracticeServer.RaceForming(c.name) end
  TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', src, buildLobbyInfo(c.name, lobbies[c.name]))
  TriggerClientEvent('dps-roxwoodracing:setLobbyState', -1, next(lobbies) ~= nil)
end)

--------------------------------------------------------------------------------
-- JOIN LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:joinLobby", function(lobbyName, vehicle)
  local src   = source
  if RateLimit(src, "joinLobby", 1000) then return end

  local lobby = lobbies[lobbyName]
  if not lobby then
    ServerNotify(src, Config.Job.label, Locale("lobby_not_found"), 'error')
    return
  end
  if lobby.isStarted then
    ServerNotify(src, Config.Job.label, 'Race already started. You cannot join now. Please come back after the race ends.', 'error')
    return
  end

  if not table_contains(lobby.players, src) then
    -- Check refund cooldown to prevent join-refund-rejoin cycling
    if _refundCD[src] then
      local elapsed = GetGameTimer() - _refundCD[src]
      if elapsed < 30000 then
        local remaining = math.ceil((30000 - elapsed) / 1000)
        ServerNotify(src, Config.Job.label, 'Please wait ' .. remaining .. ' seconds before rejoining.', 'error')
        return
      end
    end
    if #lobby.players >= #Config.GridSpawnPoints then
      ServerNotify(src, Config.Job.label, 'Lobby is full.', 'error')
      return
    end
    local openVeh
    if lobby.mode == 'open' then
      local okv, err, v = VerifyOpenVehicle(src, vehicle, lobby.class)
      if not okv then ServerNotify(src, Config.Job.label, Locale(err, Config.OpenClasses[lobby.class].label), 'error') return end
      if VehicleAlreadyRegistered(lobby, v.plate, src) then ServerNotify(src, Config.Job.label, Locale('open_not_owner'), 'error') return end
      openVeh = v
    end
    -- Charge entry fee before adding to lobby
    local paid, receipt = Rewards.ChargeEntryFee(src, lobbyName)
    if not paid then return end
    if openVeh then lobby.vehicles[src] = openVeh end
    lobby.fees[src] = receipt
    lobby.prizePool = (lobby.prizePool or 0) + (receipt and receipt.amount or 0)

    table.insert(lobby.players, src)
    -- BROADCAST who joined
    local playerName = Bridge.GetPlayerName(src)
    for _, id in ipairs(lobby.players) do
      TriggerClientEvent("dps-roxwoodracing:client:playerJoined", id, playerName)
    end
  end

  -- update everyone's lobby info
  local info = buildLobbyInfo(lobbyName, lobby)
  for _, id in ipairs(lobby.players) do
    TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", id, info)
  end
end)

--------------------------------------------------------------------------------
-- CHECKPOINT PASSED (improves ranking during a lap)
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:checkpointPassed", function(lobbyName, idx)
  local src = source
  if RateLimit(src, "checkpointPassed", 200) then return end

  local lob = lobbies[lobbyName]
  if not lob or not lob.isStarted then return end
  -- Verify player is in this lobby
  if not table_contains(lob.players, src) then return end

  local cur = lob.checkpointProgress[src] or 0
  -- Strict sequential: must be exactly the next checkpoint
  if type(idx) == 'number' and idx == cur + 1 and idx <= #Config.Checkpoints[lob.track] then
    lob.checkpointProgress[src] = idx
  end

  -- Checkpoint-based unghost: once ALL racers pass the target checkpoint, end start ghost
  if lob.ghostActive and Config.Ghosting.enabled and Config.Ghosting.unghostOnCheckpoint > 0 then
    local allPast = true
    for _, pid in ipairs(lob.players) do
      if (lob.checkpointProgress[pid] or 0) < Config.Ghosting.unghostOnCheckpoint then
        allPast = false
        break
      end
    end
    if allPast then
      lob.ghostActive = false
      for _, pid in ipairs(lob.players) do
        TriggerClientEvent("dps-roxwoodracing:client:unghost", pid)
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- LEAVE LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:leaveLobby", function()
  local src = source
  if RateLimit(src, "leaveLobby", 1000) then return end

  for name, lobby in pairs(lobbies) do
    for i, id in ipairs(lobby.players) do
      if id == src then
        -- Refund unless the race is actually under way
        if not lobby.raceLive then
          RefundLobbyFee(lobby, name, src)
          _refundCD[src] = GetGameTimer()
        end

        table.remove(lobby.players, i)
        lobby.vehicles[src] = nil
        if lobby.isStarted then
          -- Leaver after the start button: clean their client, delete a spec car, and see if the race is now over
          DeleteSpawnedVehicle(lobby, src)
          TriggerClientEvent("dps-roxwoodracing:client:destroyprops", src)
          if lobby.raceLive then TriggerClientEvent("dps-roxwoodracing:client:finishTeleport", src, Config.outCoords, lobby.mode == 'open') end
          local pc = pendingChoices[name]
          if pc then
            pc.total = math.max(0, pc.total - 1)
            if pc.selected[src] then pc.selected[src] = nil; pc.received = math.max(0, pc.received - 1) end
          end
          if #lobby.players == 0 then
            Race.EndLobby(name, 'empty')
          else
            if lobby.owner == src then lobby.owner = lobby.players[1] end
            FinishRaceIfDone(name, lobby)
          end
        elseif lobby.owner == src then
          -- owner left before the start: close lobby, refund remaining players
          for _, player in ipairs(lobby.players) do
            RefundLobbyFee(lobby, name, player)
            ServerNotify(player, Config.Job.label, Locale("lobby_closed_by_owner", name), 'warning')
            TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", player, nil)
          end
          amirState[name] = nil
          lobbies[name] = nil
          SyncPracticeState()
          PromoteSign(name)
        else
          -- member left → update remaining
          local info = buildLobbyInfo(name, lobby)
          for _, player in ipairs(lobby.players) do
            TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", player, info)
          end
        end

        -- clear leaver’s UI
        TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", src, nil)
        TriggerClientEvent("dps-roxwoodracing:setLobbyState", -1, next(lobbies) ~= nil)
        return
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- Shared vehicle spawn helper (deduplicates two identical blocks)
--------------------------------------------------------------------------------
local function SpawnRaceVehicles(lobbyName, lob, selected)
  -- Wait for the shared starting grid to clear if another lobby is mid-spawn.
  while gridLocked do Wait(250) end
  gridLocked = true

  local usedPlates = {}
  local spawnedNetIds = {}
  local failed = {}
  lob.spawned = lob.spawned or {}

  -- Record starting grid order for "Most Improved" calculation
  lob.gridOrder = {}
  for idx, pid in ipairs(lob.players) do
    lob.gridOrder[pid] = idx
  end

  for idx, pid in ipairs(lob.players) do
    local m = selected[pid]
    if not m then
      -- Slot closed on them (host left mid-picker etc.): refund and drop, never a silent skip
      RefundLobbyFee(lob, lobbyName, pid)
      TriggerClientEvent('dps-roxwoodracing:kickedFromLobby', pid, lobbyName, 'nopick')
      TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', pid, nil)
      failed[#failed+1] = pid
    else
      local sp = Config.GridSpawnPoints[idx]
      if not sp then break end -- more players than grid slots
      local veh = CreateVehicle(joaat(m), sp.x, sp.y, sp.z, sp.w, true, false)
      local deadline = GetGameTimer() + 5000
      while (not veh or veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() < deadline do Wait(50) end
      if not veh or veh == 0 or not DoesEntityExist(veh) then
        print(('[dps-roxwoodracing] spawn failed for model %s (player %s); removing from race'):format(tostring(m), tostring(pid)))
        ServerNotify(pid, Config.Job.label, Locale('race_cancelled'), 'error')
        RefundLobbyFee(lob, lobbyName, pid)
        TriggerClientEvent('dps-roxwoodracing:kickedFromLobby', pid, lobbyName, 'spawn')
        TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', pid, nil)
        failed[#failed+1] = pid
        goto nextPlayer
      end
      lob.spawned[pid] = veh
      local netId = NetworkGetNetworkIdFromEntity(veh)
      local first, last = Bridge.GetPlayerFirstLast(pid)
      local plate = Plates.FromName(first, last, GetPlayerName(pid), usedPlates)
      SetVehicleNumberPlateText(veh, plate)
      SetVehicleDoorsLocked(veh, 1)
      TriggerClientEvent("dps-roxwoodracing:client:fillFuel", pid, netId)
      TriggerClientEvent("dps-roxwoodracing:client:giveKeys", pid, netId, plate)
      TriggerClientEvent("dps-roxwoodracing:prepareStart", pid, {
        track = lob.track,
        laps  = lob.laps,
        netId = netId,
        plate = plate,
        mode  = 'spec',
        tune  = lob.tune or 'Stock',
        keepVehicle = false,
      })
      spawnedNetIds[#spawnedNetIds+1] = { pid = pid, netId = netId }
    end
    ::nextPlayer::
  end
  for _, pid in ipairs(failed) do
    for i = #lob.players, 1, -1 do if lob.players[i] == pid then table.remove(lob.players, i) end end
  end
  if #lob.players == 0 or #spawnedNetIds == 0 then
    gridLocked = false
    Race.EndLobby(lobbyName, 'spawn')
    return
  end
  if not table_contains(lob.players, lob.owner) then lob.owner = lob.players[1] end
  lob.raceLive = true
  SyncPracticeState()

  -- Broadcast all race vehicle netIds to all clients (clients ignore if not inRace)
  TriggerClientEvent("dps-roxwoodracing:raceVehicles", -1, spawnedNetIds)

  -- Start-of-race ghosting
  if Config.Ghosting.enabled and Config.Ghosting.startGhosted then
    lob.ghostActive = true
    lob.startGhostTime = GetGameTimer()
    -- Timer fallback: unghost everyone after configured seconds
    CreateThread(function()
      Wait(Config.Ghosting.unghostTimerSeconds * 1000)
      if lob.ghostActive then
        lob.ghostActive = false
        for _, pid in ipairs(lob.players) do
          TriggerClientEvent("dps-roxwoodracing:client:unghost", pid)
        end
      end
    end)
  end

  -- Release the grid lock once cars have had time to clear the start line,
  -- so a queued second lobby can spawn.
  CreateThread(function()
    Wait(8000)
    gridLocked = false
  end)
end

local function StartOpenRace(lobbyName, lob)
  while gridLocked do Wait(250) end
  gridLocked = true
  lob.gridOrder = {}
  local netIds = {}
  for idx, pid in ipairs(lob.players) do
    lob.gridOrder[pid] = idx
    local v = lob.vehicles[pid]
    local sp = Config.GridSpawnPoints[idx]
    if v and sp then
      TriggerClientEvent('dps-roxwoodracing:prepareStart', pid, {
        track = lob.track, laps = lob.laps, netId = v.netId, plate = v.plate, mode = 'open', tune = 'Stock', keepVehicle = true, grid = sp,
      })
      netIds[#netIds+1] = { pid = pid, netId = v.netId }
    end
  end
  lob.raceLive = true
  SyncPracticeState()
  TriggerClientEvent('dps-roxwoodracing:raceVehicles', -1, netIds)
  if Config.Ghosting.enabled and Config.Ghosting.startGhosted then
    lob.ghostActive = true
    CreateThread(function()
      Wait(Config.Ghosting.unghostTimerSeconds * 1000)
      if lob.ghostActive then lob.ghostActive = false; for _, pid in ipairs(lob.players) do TriggerClientEvent('dps-roxwoodracing:client:unghost', pid) end end
    end)
  end
  CreateThread(function() Wait(8000); gridLocked = false end)
end

--------------------------------------------------------------------------------
-- START RACE & VEHICLE SELECTION
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:startRace", function(lobbyName)
  local src = source
  if RateLimit(src, "startRace", 3000) then return end

  local lob = lobbies[lobbyName]
  if not lob then
    ServerNotify(src, Config.Job.label, Locale("lobby_not_found"), 'error')
    return
  end
  if lob.owner ~= src then
    ServerNotify(src, Config.Job.label, Locale("not_authorized_to_start_race"), 'error')
    return
  end
  if lob.isStarted then return end

  lob.isStarted          = true
  lob.lastLeader         = -1
  lob.progress           = {}
  lob.checkpointProgress = {}
  lob.lapProgress        = {}
  lob.startTime          = {}
  lob.lapTimes           = {}
  lob.finished           = {}

  -- The first lobby to start owns the physical AMIR LED scoreboard.
  -- Concurrent lobbies still race but don't drive the physical board.
  if not primaryLobby then primaryLobby = lobbyName end
  local isPrimary = (primaryLobby == lobbyName)

  local now = GetGameTimer()
  for _, pid in ipairs(lob.players) do
    lob.startTime[pid]   = now
    lob.lapProgress[pid] = 0
    lob.lapTimes[pid]    = {}
  end

  if Config.Leaderboard and Config.Leaderboard.enabled and isPrimary then
    -- Stop idle best-times display before switching to live race mode
    exports['dps-roxwoodracing']:StopIdleLeaderboard()

    -- reset per-lobby AMIR state
    local vm = (amirState[lobbyName] and amirState[lobbyName].vm) or (Config.Leaderboard.viewMode or "toggle")
    if vm == 'times' then vm = 'toggle' end -- coerce unsupported mode
    local startShowNames = true -- always start with names
    amirState[lobbyName] = { last = 0, key = nil, title = nil, lastSwitch = 0, showNames = startShowNames }
    -- ─ Initialize AMIR leaderboard at race start ───────────────────
    do
      local names, times = {}, {}
      for i, pid in ipairs(lob.players) do
        names[i] = Bridge.GetPlayerName(pid) or ""
        times[i] = 0
      end
      -- pad to exactly 9 entries
      for i = #names + 1, 9 do names[i], times[i] = "", 0 end
      -- show "1/totalLaps" instead of "0/totalLaps"
      local title = ("1/%d"):format(lob.laps)
      -- We always initialize with names to avoid flashing
      TriggerEvent("amir-leaderboard:setPlayerNames", title, names)
    end
    -- ───────────────────────────────────────────────────────────────
  end

  if lob.mode == 'open' then
    for _, pid in ipairs(lob.players) do TriggerClientEvent("dps-roxwoodracing:hideLobbyWindow", pid) end
    StartOpenRace(lobbyName, lob)
    return
  end

  pendingChoices[lobbyName] = { total = #lob.players, received = 0, selected = {} }
  -- Immediately hide lobby UI for all members
  for _, pid in ipairs(lob.players) do
    TriggerClientEvent("dps-roxwoodracing:hideLobbyWindow", pid)
  end
  -- Start a 30s vehicle selection countdown visible to players
  local deadline = GetGameTimer() + 30000
  CreateThread(function()
    while pendingChoices[lobbyName] do
      local now = GetGameTimer()
      local remaining = math.max(0, math.floor((deadline - now) / 1000))
      for _, pid in ipairs(lob.players) do
        TriggerClientEvent("dps-roxwoodracing:vehicleSelectCountdown", pid, remaining)
      end
      if pendingChoices[lobbyName].received >= pendingChoices[lobbyName].total then
        -- everyone selected; stop countdown
        break
      end
      if remaining <= 0 then
        break
      end
      Wait(1000)
    end

    -- Timeout or all selected; if still pending, finalize selections
    local data = pendingChoices[lobbyName]
    if not data then return end
    if data.received < data.total then
      -- kick players who didn't pick and proceed with those who did
      local keep = {}
      for i = #lob.players, 1, -1 do
        local pid = lob.players[i]
        if not data.selected[pid] then
          ServerNotify(pid, Config.Job.label, Locale("vehicle_select_timeout"), 'warning')
          RefundLobbyFee(lob, lobbyName, pid)
          TriggerClientEvent("dps-roxwoodracing:kickedFromLobby", pid, lobbyName, "timeout")
          TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", pid, nil)
          table.remove(lob.players, i)
          lob.vehicles[pid] = nil
        else
          table.insert(keep, pid)
        end
      end
      data.total = #keep
      data.received = #keep
    end

    -- If we still have players, spawn vehicles for those who selected
    if #lob.players > 0 and data.received > 0 then
      pendingChoices[lobbyName] = nil
      SpawnRaceVehicles(lobbyName, lob, data.selected)
    else
      -- nobody left or nobody selected: close the lobby properly (refunds, sign, state)
      pendingChoices[lobbyName] = nil
      Race.EndLobby(lobbyName, 'timeout')
    end
  end)
  for _, pid in ipairs(lob.players) do
    TriggerClientEvent("dps-roxwoodracing:chooseVehicle", pid, lobbyName, lob.class)
  end
end)

--------------------------------------------------------------------------------
-- VEHICLE SELECTION RESPONSE
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:selectedVehicle", function(lobbyName, model)
  local src  = source
  if RateLimit(src, "selectedVehicle", 1000) then return end

  local data = pendingChoices[lobbyName]
  local lob  = lobbies[lobbyName]
  if not data or not lob then return end
  -- Ignore submissions from players no longer in the lobby (kicked/left)
  if not table_contains(lob.players, src) then return end

  if model and not data.selected[src] then
    -- Validate model type and existence in allowed vehicle list
    if type(model) ~= 'string' then return end
    if not Lobbies.IsModelAllowed(lob.class, model) then return end
    data.selected[src] = model
    data.received = data.received + 1
  end

  if data.received == data.total then
    pendingChoices[lobbyName] = nil
    SpawnRaceVehicles(lobbyName, lob, data.selected)
  end
end)

--------------------------------------------------------------------------------
-- LIVE PROGRESS UPDATES
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:updateProgress", function(lobbyName, dist)
  local src = source
  if RateLimit(src, "updateProgress", 100) then return end
  local lob = lobbies[lobbyName]
  if not lob or not lob.isStarted then return end
  -- Verify player is in this lobby
  if not table_contains(lob.players, src) then return end
  -- Validate and clamp distance
  dist = tonumber(dist)
  if not dist or dist ~= dist then return end -- reject non-number / NaN
  dist = math.max(0, math.min(dist, 15000))

  lob.progress[src] = dist

  -- One board recompute + broadcast per lobby per 200 ms, however many racers report.
  local nowTick = GetGameTimer()
  if lob.lastBoardTick and (nowTick - lob.lastBoardTick) < 200 then return end
  lob.lastBoardTick = nowTick

  local board = {}
  for _, pid in ipairs(lob.players) do
    table.insert(board, {
      id   = pid,
      lap  = lob.lapProgress[pid] or 0,
      dist = lob.progress[pid]    or 0
    })
  end

  Ranking.SortBoard(board, lob.checkpointProgress)

  -- Broadcast leader changes to all clients for spectator cameras
  do
    if #board > 0 then
      local leaderId = board[1].id
      lob.lastLeader = lob.lastLeader or -1
      if leaderId ~= lob.lastLeader then
        lob.lastLeader = leaderId
        TriggerClientEvent('dps-roxwoodracing:leaderChanged', -1, lobbyName, leaderId)
      end
    end
  end

  if Config.DebugPrints then
    local dbg = {}
    for i, e in ipairs(board) do
      local cp = lob.checkpointProgress[e.id] or 0
      dbg[#dbg+1] = ("%d:%s lap=%d cp=%d dist=%.1f"):format(i, tostring(e.id), e.lap or 0, cp, e.dist or 0)
    end
    print("[DEBUG] leaderboard " .. table.concat(dbg, " | "))
    -- Also log which rank is sent to which player id
    for rank, e in ipairs(board) do
      local cp = lob.checkpointProgress[e.id] or 0
      local displayRank = (Config.RankingInvert and ((#board - rank) + 1)) or rank
      print(("[DEBUG] sendPosition -> id=%s rank=%d display=%d total=%d lap=%d cp=%d dist=%.1f"):format(tostring(e.id), rank, displayRank, #board, e.lap or 0, cp, e.dist or 0))
    end
  end

  for rank, e in ipairs(board) do
    local displayRank = (Config.RankingInvert and ((#board - rank) + 1)) or rank
    TriggerClientEvent("dps-roxwoodracing:updatePosition", e.id, displayRank, #board)
  end

  -- Lapped-player ghosting: ghost players a full lap behind the leader
  if Config.Ghosting.enabled and Config.Ghosting.lappedGhosting then
    local leaderLap = board[1] and board[1].lap or 0
    for _, entry in ipairs(board) do
      local isLapped = (leaderLap - entry.lap) >= 1
      local wasGhosted = lob.lappedGhost and lob.lappedGhost[entry.id]
      if isLapped and not wasGhosted then
        lob.lappedGhost = lob.lappedGhost or {}
        lob.lappedGhost[entry.id] = true
        TriggerClientEvent("dps-roxwoodracing:client:setGhosted", entry.id, true)
      elseif not isLapped and wasGhosted then
        lob.lappedGhost[entry.id] = nil
        TriggerClientEvent("dps-roxwoodracing:client:setGhosted", entry.id, false)
      end
    end
  end

  -- Update AMIR leaderboard to reflect live positions and current lap/total.
  -- Only the primary lobby drives the physical LED scoreboard.
  if Config.Leaderboard and Config.Leaderboard.enabled and primaryLobby == lobbyName then
    local lName = lobbyName
    -- derive a deterministic key for ordering (IDs joined by '-')
    local keyParts = {}
    for i, e in ipairs(board) do keyParts[i] = tostring(e.id) end
    local orderKey = table.concat(keyParts, "-")
    -- Displayed lap should be current lap number (completed+1), clamped to total
    local leaderLapDisplay = 1
    for _, e in ipairs(board) do
      local lp = (lob.lapProgress[e.id] or 0) + 1
      if lp > lob.laps then lp = lob.laps end
      if lp > leaderLapDisplay then leaderLapDisplay = lp end
    end
    local title = ("%d/%d"):format(leaderLapDisplay, lob.laps)

    -- Throttle and only push when content actually changes to prevent flashing
  local st = amirState[lName] or { last = 0, key = nil, title = nil, lastSwitch = 0, showNames = true }
  local now = GetGameTimer()
  local interval   = (Config.Leaderboard.updateIntervalMs or 1000)
  local toggleInt  = (Config.Leaderboard.toggleIntervalMs or 2000)
  local vm         = (st and st.vm) or (Config.Leaderboard.viewMode or "toggle")
  if vm == 'times' then vm = 'toggle' end -- coerce unsupported mode

    -- Decide which view should be active now and whether we just switched this tick
    local showNames = st.showNames ~= false -- default true
    local switched  = false
    if vm == "toggle" then
      if (now - (st.lastSwitch or 0)) >= toggleInt then
        showNames      = not showNames
        st.lastSwitch  = now
        switched       = true
      end
    elseif vm == "names" then
      showNames = true
    else -- vm == "times"
      showNames = false
    end

  -- Only push when:
  --  - order or title changed (rank/lap changes)
  --  - toggle just switched modes
    local contentChanged = (st.key ~= orderKey) or (st.title ~= title)
    local timeForInterval = (now - (st.last or 0)) >= interval
  local shouldPush = contentChanged or switched

    if shouldPush then
      local names, times = {}, {}
      local maxEntries = 9
      local count = math.min(#board, maxEntries)
      for i = 1, count do
        local pid = board[i].id
        names[i] = Bridge.GetPlayerName(pid) or ""
        -- Always provide times for the AMIR toggle view.
        -- Times are milliseconds, AMIR displays them as MM:SS.
        local tmode = (Config.Leaderboard and Config.Leaderboard.timeMode) or "total" -- "total" or "lap"
        local finished = lob.finished[pid] == true
        if tmode == "lap" then
          if finished then
            -- show the final lap time for finished racers
            local arr = lob.lapTimes[pid] or {}
            local last = arr[#arr] or 0
            times[i] = last
          else
            local lapStart = lob.startTime[pid] or now
            local lapMs    = now - lapStart
            if lapMs < 0 then lapMs = 0 end
            times[i] = lapMs
          end
        else
          -- total time: freeze at final total for finished racers; otherwise keep running
          local sum = 0
          local arr = lob.lapTimes[pid] or {}
          for _, t in ipairs(arr) do sum = sum + t end
          if finished then
            times[i] = sum
          else
            local lapStart = lob.startTime[pid] or now
            local currLap  = now - lapStart
            if currLap < 0 then currLap = 0 end
            times[i] = sum + currLap
          end
        end
      end
      for i = count + 1, maxEntries do names[i], times[i] = "", 0 end

      if showNames then
        TriggerEvent("amir-leaderboard:setPlayerNames", title, names)
      else
        TriggerEvent("amir-leaderboard:setPlayerTimes", title, times)
      end

      -- Persist state; note we intentionally do not include vm here, it's read from config/override
      amirState[lName] = { last = now, key = orderKey, title = title, lastSwitch = st.lastSwitch, showNames = showNames, vm = vm }
    end
  end
end)

--------------------------------------------------------------------------------
-- LAP PASSED, LEADERBOARD UPDATE & RACE END
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:lapPassed", function(lobbyName)
  local src = source
  if RateLimit(src, "lapPassed", 500) then return end

  local lob = lobbies[lobbyName]
  if not lob then return end
  -- Verify player is in this lobby
  if not table_contains(lob.players, src) then return end
  -- Prevent double-finish
  if lob.finished[src] then return end
  -- Verify ALL checkpoints were passed before counting the lap
  if (lob.checkpointProgress[src] or 0) < #Config.Checkpoints[lob.track] then return end

  -- advance lap count
  lob.lapProgress[src] = (lob.lapProgress[src] or 0) + 1
  local curLap = lob.lapProgress[src]

  -- record lap time
  local now = GetGameTimer()
  table.insert(lob.lapTimes[src], now - (lob.startTime[src] or now))
  lob.startTime[src] = now

  -- notify client of the current lap to display: completed+1, clamped to total
  local displayLap = curLap + 1
  if displayLap > lob.laps then displayLap = lob.laps end
  TriggerClientEvent("dps-roxwoodracing:updateLap", src, displayLap, lob.laps)

  -- reset per-lap progress counters so sorting is fair at the new lap start
  lob.checkpointProgress[src] = 0
  lob.progress[src] = 0

  -- Leaderboard updates are handled continuously in updateProgress to reflect live positions

  -- if they’ve now completed the total number of laps…
  if curLap >= lob.laps then
    if not lob.finished[src] then
      lob.finished[src] = true

      -- warp them back, fade in/out
      TriggerClientEvent("dps-roxwoodracing:client:finishTeleport", src, Config.outCoords, lob.mode == 'open')
      -- important “You finished!” toast
      TriggerClientEvent("dps-roxwoodracing:youFinished", src)

      -- push their personal result
      local totalT, best = 0, math.huge
      for _, t in ipairs(lob.lapTimes[src]) do
        totalT, best = totalT + t, math.min(best, t)
      end
      if best == math.huge then best = 0 end

      TriggerClientEvent("dps-roxwoodracing:finalRanking", src, {
        position  = table_count(lob.finished),
        totalTime = totalT,
        lapTimes  = lob.lapTimes[src],
        bestLap   = best
      })
    end

    FinishRaceIfDone(lobbyName, lob)
  end
end)

FinishRaceIfDone = function(lobbyName, lob)
  -- once everyone’s finished, broadcast the podium and tear down
  local allFin = true
  for _, pid in ipairs(lob.players) do
    if not lob.finished[pid] then allFin = false break end
  end
  if allFin then
    local results, bestLapPlayer, mostImprovedId = Ranking.BuildResults(lob.players, lob.lapTimes, lob.gridOrder,
      function(pid) return Bridge.GetPlayerName(pid) or ('Player ' .. pid) end)

    -- Pay everyone through the society account, then stamp totals onto the results
    lob.name = lobbyName
    local payouts, purseCovered = Rewards.Settle(lob, results, bestLapPlayer)
    for _, entry in ipairs(results) do entry.payout = payouts[entry.id] and payouts[entry.id].total or 0 end

    -- Broadcast expanded results to all race participants
    for _, pid in ipairs(lob.players) do
      TriggerClientEvent("dps-roxwoodracing:finalRanking", pid, {
        allResults = results,
        bestLapPlayer = bestLapPlayer,
        mostImprovedPlayer = mostImprovedId,
        track = lob.track,
        purseCovered = purseCovered,
      })
      TriggerClientEvent("dps-roxwoodracing:client:destroyprops", pid)
    end

    -- Save persistent race stats for each player.
    -- Each call is wrapped in CreateThread so the per-player DB queries
    -- run concurrently instead of serializing on a full grid.
    for pos, entry in ipairs(results) do
      local totalEarnings = entry.payout or 0
      local pidLocal, posLocal, bestLapLocal = entry.id, pos, entry.bestLap or 0
      CreateThread(function()
        Stats.Save(pidLocal, posLocal, lob.track, bestLapLocal, totalEarnings, lob.mode)
      end)
    end

    -- Reset leader tracking for this lobby
    lob.lastLeader = -1

    amirState[lobbyName] = nil
    lobbies[lobbyName] = nil
  SyncPracticeState()
    TriggerClientEvent("dps-roxwoodracing:setLobbyState", -1, next(lobbies) ~= nil)

    -- If this was the primary lobby, promote the next active lobby to drive
    -- the physical AMIR LED scoreboard. If none is running, resume the idle
    -- best-times display.
    local wasPrimary = (primaryLobby == lobbyName)
    if wasPrimary then
      primaryLobby = nil
      for nextName, nextLob in pairs(lobbies) do
        if nextLob.isStarted then
          primaryLobby = nextName
          break
        end
      end
    end

    if Config.Leaderboard and Config.Leaderboard.enabled and wasPrimary and not primaryLobby then
      exports['dps-roxwoodracing']:ShowIdleLeaderboard()
    end
  end
  
end

--------------------------------------------------------------------------------
-- FINISH TELEPORT, FUEL, ETC.
--------------------------------------------------------------------------------
-- Fuel sync from a pit stop: only for a racer's own race car, only while it sits in a pit box.
local function AuthorisedFuelVehicle(src, netId)
  netId = tonumber(netId)
  if not netId then return nil end
  local name, lob = findLobbyByPlayer(src)
  if not lob or not lob.isStarted then return nil end
  local mine = (lob.spawned and lob.spawned[src] and NetworkGetNetworkIdFromEntity(lob.spawned[src]) == netId)
            or (lob.vehicles and lob.vehicles[src] and lob.vehicles[src].netId == netId)
  if not mine then return nil end
  local v = NetworkGetEntityFromNetworkId(netId)
  if not v or v == 0 or not DoesEntityExist(v) then return nil end
  local pos = GetEntityCoords(v)
  for _, zone in ipairs(Config.PitCrewZones) do
    if #(pos - vector3(zone.coords.x, zone.coords.y, zone.coords.z)) <= (zone.radius + 6.0) then return v end
  end
  return nil
end

RegisterNetEvent("dps-roxwoodracing:server:setFuel", function(netId, level)
  local src = source
  if RateLimit(src, "setFuel", 150) then return end
  level = tonumber(level)
  if not level then return end
  if level < 0 then level = 0 end; if level > 100 then level = 100 end
  local v = AuthorisedFuelVehicle(src, netId)
  if not v then return end
  if GetResourceState("ox_fuel") == "started" then
    local st = Entity(v).state
    if st and st.set then st:set("fuel", level + 0.0, true) end
  end
  TriggerClientEvent('dps-roxwoodracing:client:setFuel', -1, netId, level + 0.0)
end)

-- Remove a player from whatever lobby they are in: disconnect, character unload, or a client
-- that could not stream its race car. Refunds if the race never went live, deletes their spec car,
-- promotes a new host, finishes the race if the others are done, closes an empty lobby.
local function RemovePlayer(src, reason)
  local name, lob = findLobbyByPlayer(src)
  if not lob then return end
  for i = #lob.players, 1, -1 do if lob.players[i] == src then table.remove(lob.players, i) end end
  lob.vehicles[src] = nil
  DeleteSpawnedVehicle(lob, src)
  if not lob.raceLive or reason == 'spawnfail' then RefundLobbyFee(lob, name, src) end
  if #lob.players == 0 then
    Race.EndLobby(name, 'empty')
    return
  end
  if lob.owner == src then lob.owner = lob.players[1] end
  local pc = pendingChoices[name]
  if pc then
    pc.total = math.max(0, pc.total - 1)
    if pc.selected[src] then pc.selected[src] = nil; pc.received = math.max(0, pc.received - 1) end
  end
  if lob.isStarted then
    FinishRaceIfDone(name, lob)
  else
    local info = buildLobbyInfo(name, lob)
    for _, pid in ipairs(lob.players) do TriggerClientEvent("dps-roxwoodracing:updateLobbyInfo", pid, info) end
  end
end

AddEventHandler('playerDropped', function() RemovePlayer(source, 'dropped') end)
-- Multichar switch: source survives, the character does not. Same cleanup as a disconnect.
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) RemovePlayer(src, 'unload') end)

-- The client could not resolve its race car within its own timeout: treat it like a failed spawn.
RegisterNetEvent('dps-roxwoodracing:spawnFailed', function(lobbyName)
  local src = source
  if RateLimit(src, 'spawnFailed', 2000) then return end
  local lob = lobbies[lobbyName]
  if not lob or not table_contains(lob.players, src) then return end
  if (lob.lapProgress[src] or 0) > 0 or (lob.checkpointProgress[src] or 0) > 0 then return end
  TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', src, nil)
  RemovePlayer(src, 'spawnfail')
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  for _, lob in pairs(lobbies) do
    for pid in pairs(lob.spawned or {}) do DeleteSpawnedVehicle(lob, pid) end
  end
end)

--------------------------------------------------------------------------------
-- LEADERBOARD: show idle best-times on resource start
--------------------------------------------------------------------------------
if Config.Leaderboard and Config.Leaderboard.enabled then
  CreateThread(function()
    Wait(3000)
    exports['dps-roxwoodracing']:ShowIdleLeaderboard()
  end)
end
