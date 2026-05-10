-- s_main.lua

local Config    = require("config.config")
-- Bridge (loaded before this file via fxmanifest) provides: Bridge.Framework,
-- Bridge.GetPlayerIdentifier(), Bridge.AddMoney(), etc.
local localeTable = require("locales." .. Config.Locale)
local function locale(key, ...)
  local str = localeTable[key] or key
  local args = { ... }
  return (str:gsub("{(%d+)}", function(n)
    return tostring(args[tonumber(n)] or "")
  end))
end

--------------------------------------------------------------------------------
-- server-side notification helper (routes through client SpeedwayNotify)
--------------------------------------------------------------------------------
local function ServerNotify(target, title, description, ntype, duration)
  TriggerClientEvent('speedway:client:notify', target, title, description, ntype, duration)
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
local VALID_TRACKS = {}
for k in pairs(Config.Checkpoints) do VALID_TRACKS[k] = true end

local VALID_CLASSES = {}
for k in pairs(Config.RaceClasses) do VALID_CLASSES[k] = true end

local VALID_MODELS = {}
for _, v in ipairs(Config.RaceVehicles) do VALID_MODELS[v.model:lower()] = true end

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
-- Database: auto-create stats table on resource start
--------------------------------------------------------------------------------
if Config.Stats and Config.Stats.enabled then
  CreateThread(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS speedway_stats (
        citizenid VARCHAR(50) NOT NULL,
        total_races INT DEFAULT 0,
        wins INT DEFAULT 0,
        top3 INT DEFAULT 0,
        total_earnings INT DEFAULT 0,
        best_laps JSON DEFAULT '{}',
        last_race TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (citizenid)
      )
    ]])
    print('[Speedway] speedway_stats table ready.')
  end)
end

--------------------------------------------------------------------------------
-- Helper: get citizenid from server id
--------------------------------------------------------------------------------
local function GetCitizenId(pid)
  return Bridge.GetPlayerIdentifier(pid)
end

--------------------------------------------------------------------------------
-- Rewards: grant money and prizes at race end
--------------------------------------------------------------------------------
local function GrantRewards(lob, results, lobbyName)
  if not Config.Rewards or not Config.Rewards.enabled then return end
  if not Bridge.Framework then return end

  -- Find best lap across all players
  local globalBestLap = math.huge
  local bestLapPlayer = nil
  for _, pid in ipairs(lob.players) do
    for _, t in ipairs(lob.lapTimes[pid] or {}) do
      if t < globalBestLap then
        globalBestLap = t
        bestLapPlayer = pid
      end
    end
  end

  for pos, entry in ipairs(results) do
    local pid = entry.id
    -- Skip players who disconnected before payout (bridge returns false if offline)
    if not Bridge.GetPlayerIdentifier(pid) then goto continueReward end

    local totalPayout = 0
    local positionPayout = Config.Rewards.payouts[pos] or 0
    local positionLabel = tostring(pos)
    if pos == 1 then positionLabel = "1st"
    elseif pos == 2 then positionLabel = "2nd"
    elseif pos == 3 then positionLabel = "3rd"
    else positionLabel = pos .. "th" end

    -- Position payout
    if positionPayout > 0 then
      Bridge.AddMoney(pid, Config.Rewards.moneyType, positionPayout, 'speedway-race')
      totalPayout = totalPayout + positionPayout
    end

    -- Participation reward
    local participation = Config.Rewards.participationReward or 0
    if participation > 0 then
      Bridge.AddMoney(pid, Config.Rewards.moneyType, participation, 'speedway-participation')
      totalPayout = totalPayout + participation
    end

    -- Best lap bonus
    local bestLapBonus = 0
    if pid == bestLapPlayer and Config.Rewards.bestLapBonus and Config.Rewards.bestLapBonus > 0 then
      bestLapBonus = Config.Rewards.bestLapBonus
      Bridge.AddMoney(pid, Config.Rewards.moneyType, bestLapBonus, 'speedway-bestlap')
      totalPayout = totalPayout + bestLapBonus
    end

    -- Vehicle prize for 1st place
    local vehiclePrize = nil
    if pos == 1 and Config.Rewards.vehiclePrize then
      vehiclePrize = Config.Rewards.vehiclePrize
      local plate = 'PRIZE' .. math.random(100, 999)
      Bridge.InsertVehicle(pid, vehiclePrize, plate, Config.Rewards.vehiclePrizeGarage or 'pillboxgarage')
    end

    -- Notify client
    TriggerClientEvent('speedway:client:rewardNotify', pid, {
      positionPayout = positionPayout,
      positionLabel = positionLabel,
      participation = participation,
      bestLapBonus = bestLapBonus,
      vehiclePrize = vehiclePrize,
      totalPayout = totalPayout,
    })

    ::continueReward::
  end
end

--------------------------------------------------------------------------------
-- Entry Fee: distribute prize pool at race end
--------------------------------------------------------------------------------
local function DistributePrizePool(lob, results)
  if not Config.EntryFee or not Config.EntryFee.enabled then return end
  if not Bridge.Framework then return end
  local pool = lob.prizePool or 0
  if pool <= 0 then return end

  for pos, entry in ipairs(results) do
    local pct = Config.EntryFee.poolSplit[pos]
    if pct and pct > 0 then
      local payout = math.floor(pool * pct / 100)
      if payout > 0 and Bridge.AddMoney(entry.id, Config.EntryFee.moneyType or 'cash', payout, 'speedway-prizepool') then
        TriggerClientEvent('speedway:client:rewardNotify', entry.id, { poolPayout = payout })
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Stats: save race stats to database
--------------------------------------------------------------------------------
local function SaveRaceStats(pid, position, track, bestLap, earnings)
  if not Config.Stats or not Config.Stats.enabled then return end
  local cid = GetCitizenId(pid)
  if not cid then return end

  local isWin = position == 1 and 1 or 0
  local isTop3 = position <= 3 and 1 or 0

  -- Fetch existing best_laps JSON to merge
  local existing = MySQL.scalar.await('SELECT best_laps FROM speedway_stats WHERE citizenid = ?', { cid })
  local bestLaps = {}
  if existing then
    bestLaps = json.decode(existing) or {}
  end

  local newRecord = false
  if bestLap and bestLap > 0 then
    if not bestLaps[track] or bestLap < bestLaps[track] then
      bestLaps[track] = bestLap
      newRecord = true
    end
  end

  MySQL.query.await([[
    INSERT INTO speedway_stats (citizenid, total_races, wins, top3, total_earnings, best_laps, last_race)
    VALUES (?, 1, ?, ?, ?, ?, NOW())
    ON DUPLICATE KEY UPDATE
      total_races = total_races + 1,
      wins = wins + ?,
      top3 = top3 + ?,
      total_earnings = total_earnings + ?,
      best_laps = ?,
      last_race = NOW()
  ]], { cid, isWin, isTop3, earnings or 0, json.encode(bestLaps), isWin, isTop3, earnings or 0, json.encode(bestLaps) })

  -- Get updated stats to notify client
  if Config.Stats.showAfterRace then
    local row = MySQL.single.await('SELECT * FROM speedway_stats WHERE citizenid = ?', { cid })
    if row then
      local laps = json.decode(row.best_laps or '{}') or {}
      TriggerClientEvent('speedway:client:statsNotify', pid, {
        wins = row.wins,
        totalRaces = row.total_races,
        bestLap = laps[track],
        newRecord = newRecord and bestLap or nil,
      })
    end
  end
end

--------------------------------------------------------------------------------
-- Stats callback for /racestats command
--------------------------------------------------------------------------------
lib.callback.register('speedway:getPlayerStats', function(source)
  local cid = GetCitizenId(source)
  if not cid then return nil end
  local row = MySQL.single.await('SELECT * FROM speedway_stats WHERE citizenid = ?', { cid })
  if not row then return nil end
  row.best_laps = json.decode(row.best_laps or '{}') or {}
  return row
end)

--------------------------------------------------------------------------------
-- Entry Fee: helper to charge/refund
--------------------------------------------------------------------------------
local function ChargeEntryFee(pid)
  if not Config.EntryFee or not Config.EntryFee.enabled then return true end
  if not Bridge.Framework then return true end
  local amount = Config.EntryFee.amount or 0
  if amount <= 0 then return true end
  local moneyType = Config.EntryFee.moneyType or 'cash'
  if Bridge.GetMoney(pid, moneyType) < amount then
    ServerNotify(pid, 'Speedway', locale("entry_fee_insufficient", amount), 'error')
    return false
  end
  Bridge.RemoveMoney(pid, moneyType, amount, 'speedway-entryfee')
  ServerNotify(pid, 'Speedway', locale("entry_fee_charged", amount), 'inform')
  return true
end

local function RefundEntryFee(pid)
  if not Config.EntryFee or not Config.EntryFee.enabled then return end
  if not Bridge.Framework then return end
  local amount = Config.EntryFee.amount or 0
  if amount <= 0 then return end
  Bridge.AddMoney(pid, Config.EntryFee.moneyType or 'cash', amount, 'speedway-entryfee-refund')
  ServerNotify(pid, 'Speedway', locale("entry_fee_refunded", amount), 'success')
end

--------------------------------------------------------------------------------
-- lobby storage
--------------------------------------------------------------------------------
local lobbies        = {}    -- [lobbyName] = { owner, track, laps, players, ... }
local pendingChoices = {}    -- for vehicle selection
local amirState      = {}    -- per-lobby AMIR throttle and last state

-- Helper: build a license plate string from a player's character name (fallback to Rockstar name)
-- - Uppercase alphanumerics only
-- - Max 8 characters (GTA V plate limit)
-- - Optionally uniquified with digits if a collision occurs within the same spawn batch
local function makePlateFromPlayer(pid, used)
  local first, last = Bridge.GetPlayerFirstLast(pid)

  local function san(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("%s+", ""):upper():gsub("[^A-Z0-9]", "")
    return s
  end

  local candidates = {}
  -- Prefer full name smashed if it fits/exists
  if first or last then
    table.insert(candidates, san((first or "") .. (last or "")))
    -- Also try first initial + last (keeps surname readable in 8 chars)
    local fi = first and first:sub(1,1) or ""
    table.insert(candidates, san(fi .. (last or "")))
  end
  -- Fallback to Rockstar name
  table.insert(candidates, san(GetPlayerName(pid) or ""))
  -- Final fallback
  table.insert(candidates, "SPD")

  local str = "SPD"
  for _, c in ipairs(candidates) do
    if c and #c > 0 then str = c break end
  end
  if #str > 8 then str = str:sub(1, 8) end

  -- Ensure uniqueness within the provided 'used' set by appending digits, trimming if needed
  if used then
    local base = str
    local suffix = 0
    while used[str] do
      suffix = suffix + 1
      local suf = tostring(suffix)
      local take = math.max(0, 8 - #suf)
      str = base:sub(1, take) .. suf
    end
    used[str] = true
  end

  if Config.DebugPrints then
    print(('[DEBUG] Plate for %s -> %s'):format(tostring(pid), str))
  end
  return str
end

-- Helper: find lobby by player id
local function findLobbyByPlayer(pid)
  for name, lob in pairs(lobbies) do
    for _, p in ipairs(lob.players or {}) do
      if p == pid then return name, lob end
    end
  end
  return nil, nil
end

-- Admin/host command to change AMIR view mode at runtime
-- Usage:
--   /lb names
--   /lb toggle
--   From server console, pass lobby name as 2nd arg: lb names <LobbyName>
RegisterCommand('lb', function(src, args)
  local mode = args and args[1] and args[1]:lower() or nil
  if mode ~= 'names' and mode ~= 'toggle' then
    if src == 0 then
      print('[Speedway] Usage: lb <names|toggle> [LobbyName]')
    else
      ServerNotify(src, 'Speedway', 'Usage: /lb names | toggle', 'inform')
    end
    return
  end

  local lobbyName, lob
  if src == 0 then
    lobbyName = args[2]
    if not lobbyName then lobbyName = next(lobbies) end
    lob = lobbyName and lobbies[lobbyName] or nil
  else
    lobbyName, lob = findLobbyByPlayer(src)
  end

  if not lob then
    if src == 0 then
      print('[Speedway] No active lobby found for command')
    else
      ServerNotify(src, 'Speedway', 'No active lobby found', 'error')
    end
    return
  end

  amirState[lobbyName] = amirState[lobbyName] or { last = 0, key = nil, title = nil, lastSwitch = 0, showNames = true }
  amirState[lobbyName].vm = mode
  amirState[lobbyName].last = 0       -- force next push
  amirState[lobbyName].lastSwitch = 0 -- reset toggle timer
  amirState[lobbyName].showNames = true -- always start on names view

  local msg = ('AMIR view mode set to %s for lobby %s'):format(mode, tostring(lobbyName))
  if src == 0 then print('[Speedway] ' .. msg) else ServerNotify(src, locale('speedway_title'), msg, 'success') end
end, false)

math.randomseed(GetGameTimer())

--------------------------------------------------------------------------------
-- callbacks for client queries
--------------------------------------------------------------------------------
lib.callback.register("speedway:getLobbies", function(source)
  local result = {}
  for name, lobby in pairs(lobbies) do
    table.insert(result, {
      label = locale("lobby_label_template", name, lobby.track, #lobby.players),
      value = name
    })
  end
  return result
end)

lib.callback.register("speedway:getLobbyPlayers", function(source, lobbyName)
  local lobby = lobbies[lobbyName]
  return lobby and lobby.players or {}
end)

--------------------------------------------------------------------------------
-- CREATE LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:createLobby", function(lobbyName, trackType, lapCount, raceClass)
  local src = source
  if RateLimit(src, "createLobby", 2000) then return end

  -- Validate lobbyName: must be a string, 1-50 chars, alphanumeric+underscore only
  if type(lobbyName) ~= 'string' or #lobbyName < 1 or #lobbyName > 50 or lobbyName:find('[^%w_]') then
    ServerNotify(src, 'Speedway', 'Invalid lobby name (alphanumeric/underscore, 1-50 chars).', 'error')
    return
  end
  -- Validate trackType: must exist in config
  if type(trackType) ~= 'string' or not VALID_TRACKS[trackType] then
    ServerNotify(src, 'Speedway', 'Invalid track selection.', 'error')
    return
  end
  -- Validate lapCount: integer 1-10
  lapCount = tonumber(lapCount)
  if not lapCount or lapCount ~= math.floor(lapCount) or lapCount < 1 or lapCount > 10 then
    ServerNotify(src, 'Speedway', 'Invalid lap count (must be 1-10).', 'error')
    return
  end
  -- Validate raceClass: must exist in config, default to 'All'
  if raceClass == nil then raceClass = 'All' end
  if type(raceClass) ~= 'string' or not VALID_CLASSES[raceClass] then raceClass = 'All' end

  if Config.DebugPrints then
    print(string.format("[DEBUG] speedway:createLobby received: lobbyName=%s, trackType=%s, lapCount=%s, raceClass=%s, src=%s", lobbyName, trackType, lapCount, tostring(raceClass), src))
  end

  -- Prevent new lobby if any lobby is active
  if next(lobbies) ~= nil then
    if Config.DebugPrints then print("[DEBUG] Cannot create lobby: another lobby is already active.") end
    ServerNotify(src, 'Speedway', locale("lobby_exists"), 'error')
    return
  end
  if lobbies[lobbyName] then
    if Config.DebugPrints then print("[DEBUG] Lobby already exists: " .. lobbyName) end
    ServerNotify(src, 'Speedway', locale("lobby_exists"), 'error')
    return
  end

  -- Charge entry fee to creator
  if not ChargeEntryFee(src) then return end

  local entryFeeAmount = (Config.EntryFee and Config.EntryFee.enabled) and (Config.EntryFee.amount or 0) or 0

  lobbies[lobbyName] = {
    owner              = src,
    track              = trackType,
    laps               = lapCount or 1,
    raceClass          = raceClass or 'All',
    players            = { src },
    checkpointProgress = {},
    isStarted          = false,
    lapProgress        = {},
    finished           = {},
    lapTimes           = {},
    startTime          = {},
    progress           = {},
    prizePool          = entryFeeAmount,
  }
  if Config.DebugPrints then print("[DEBUG] Lobby created: " .. lobbyName) end

  -- tell the creator
  ServerNotify(src, 'Speedway', locale("lobby_created", lobbyName), 'success')
  local hostName = GetPlayerName(src)
  TriggerClientEvent('speedway:updateLobbyInfo', src, {
    name      = lobbyName,
    hostName  = hostName,
    track     = trackType,
    players   = lobbies[lobbyName].players,
    owner     = src,
    laps      = lobbies[lobbyName].laps
  })
  TriggerClientEvent('speedway:setLobbyState', -1, next(lobbies) ~= nil)
  if Config.DebugPrints then print("[DEBUG] Lobby info sent to client and lobby state updated.") end
end)

--------------------------------------------------------------------------------
-- JOIN LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:joinLobby", function(lobbyName)
  local src   = source
  if RateLimit(src, "joinLobby", 1000) then return end

  local lobby = lobbies[lobbyName]
  if not lobby then
    ServerNotify(src, 'Speedway', locale("lobby_not_found"), 'error')
    return
  end
  if lobby.isStarted then
    ServerNotify(src, 'Speedway', 'Race already started. You cannot join now. Please come back after the race ends.', 'error')
    return
  end

  if not table_contains(lobby.players, src) then
    -- Check refund cooldown to prevent join-refund-rejoin cycling
    if _refundCD[src] then
      local elapsed = GetGameTimer() - _refundCD[src]
      if elapsed < 30000 then
        local remaining = math.ceil((30000 - elapsed) / 1000)
        ServerNotify(src, 'Speedway', 'Please wait ' .. remaining .. ' seconds before rejoining.', 'error')
        return
      end
    end
    -- Charge entry fee before adding to lobby
    if not ChargeEntryFee(src) then return end
    local entryFeeAmount = (Config.EntryFee and Config.EntryFee.enabled) and (Config.EntryFee.amount or 0) or 0
    lobby.prizePool = (lobby.prizePool or 0) + entryFeeAmount

    table.insert(lobby.players, src)
    -- BROADCAST who joined
    local playerName = GetPlayerName(src)
    for _, id in ipairs(lobby.players) do
      TriggerClientEvent("speedway:client:playerJoined", id, playerName)
    end
  end

  -- update everyone’s lobby info
  for _, id in ipairs(lobby.players) do
    TriggerClientEvent("speedway:updateLobbyInfo", id, {
      name     = lobbyName,
      hostName = GetPlayerName(lobby.owner),
      track    = lobby.track,
      players  = lobby.players,
      owner    = lobby.owner,
      laps     = lobby.laps
    })
  end
end)

--------------------------------------------------------------------------------
-- CHECKPOINT PASSED (improves ranking during a lap)
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:checkpointPassed", function(lobbyName, idx)
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
        TriggerClientEvent("speedway:client:unghost", pid)
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- LEAVE LOBBY
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:leaveLobby", function()
  local src = source
  if RateLimit(src, "leaveLobby", 1000) then return end

  for name, lobby in pairs(lobbies) do
    for i, id in ipairs(lobby.players) do
      if id == src then
        -- Refund entry fee if race hasn't started
        if not lobby.isStarted then
          RefundEntryFee(src)
          _refundCD[src] = GetGameTimer()
          local entryFeeAmount = (Config.EntryFee and Config.EntryFee.enabled) and (Config.EntryFee.amount or 0) or 0
          lobby.prizePool = math.max(0, (lobby.prizePool or 0) - entryFeeAmount)
        end

        table.remove(lobby.players, i)
        if lobby.owner == src then
          -- owner left → close lobby, refund remaining players if race hasn't started
          for _, player in ipairs(lobby.players) do
            if not lobby.isStarted then
              RefundEntryFee(player)
            end
            ServerNotify(player, 'Speedway', locale("lobby_closed_by_owner", name), 'warning')
            TriggerClientEvent("speedway:updateLobbyInfo", player, nil)
          end
          lobbies[name] = nil
        else
          -- member left → update remaining
          for _, player in ipairs(lobby.players) do
            TriggerClientEvent("speedway:updateLobbyInfo", player, {
              name     = name,
              hostName = GetPlayerName(lobby.owner),
              track    = lobby.track,
              players  = lobby.players,
              owner    = lobby.owner,
              laps     = lobby.laps
            })
          end
        end

        -- clear leaver’s UI
        TriggerClientEvent("speedway:updateLobbyInfo", src, nil)
        TriggerClientEvent("speedway:setLobbyState", -1, next(lobbies) ~= nil)
        return
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- Shared vehicle spawn helper (deduplicates two identical blocks)
--------------------------------------------------------------------------------
local function SpawnRaceVehicles(lobbyName, lob, selected)
  local usedPlates = {}
  local spawnedNetIds = {}
  TriggerClientEvent('rox_speedway:cam:broadcastOn', -1)

  -- Record starting grid order for "Most Improved" calculation
  lob.gridOrder = {}
  for idx, pid in ipairs(lob.players) do
    lob.gridOrder[pid] = idx
  end

  for idx, pid in ipairs(lob.players) do
    local m = selected[pid]
    if m then
      local sp = Config.GridSpawnPoints[idx]
      if not sp then break end -- more players than grid slots
      local veh = CreateVehicle(joaat(m), sp.x, sp.y, sp.z, sp.w, true, false)
      while not DoesEntityExist(veh) do Wait(0) end
      local netId = NetworkGetNetworkIdFromEntity(veh)
      local plate = makePlateFromPlayer(pid, usedPlates)
      SetVehicleNumberPlateText(veh, plate)
      SetVehicleDoorsLocked(veh, 1)
      TriggerClientEvent("speedway:client:fillFuel", pid, netId)
      TriggerClientEvent("speedway:client:giveKeys", pid, netId)
      TriggerClientEvent("speedway:prepareStart", pid, {
        track = lob.track,
        laps  = lob.laps,
        netId = netId,
        plate = plate,
      })
      spawnedNetIds[#spawnedNetIds+1] = { pid = pid, netId = netId }
    end
  end

  -- Broadcast all race vehicle netIds to all clients (clients ignore if not inRace)
  TriggerClientEvent("speedway:raceVehicles", -1, spawnedNetIds)

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
          TriggerClientEvent("speedway:client:unghost", pid)
        end
      end
    end)
  end
end

--------------------------------------------------------------------------------
-- START RACE & VEHICLE SELECTION
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:startRace", function(lobbyName)
  local src = source
  if RateLimit(src, "startRace", 3000) then return end

  local lob = lobbies[lobbyName]
  if not lob then
    ServerNotify(src, 'Speedway', locale("lobby_not_found"), 'error')
    return
  end
  if lob.owner ~= src then
    ServerNotify(src, 'Speedway', locale("not_authorized_to_start_race"), 'error')
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

  local now = GetGameTimer()
  for _, pid in ipairs(lob.players) do
    lob.startTime[pid]   = now
    lob.lapProgress[pid] = 0
    lob.lapTimes[pid]    = {}
  end

  if Config.Leaderboard and Config.Leaderboard.enabled then
    -- Stop idle best-times display before switching to live race mode
    exports['rox_speedway']:StopIdleLeaderboard()

    -- reset per-lobby AMIR state
    local vm = (amirState[lobbyName] and amirState[lobbyName].vm) or (Config.Leaderboard.viewMode or "toggle")
    if vm == 'times' then vm = 'toggle' end -- coerce unsupported mode
    local startShowNames = true -- always start with names
    amirState[lobbyName] = { last = 0, key = nil, title = nil, lastSwitch = 0, showNames = startShowNames }
    -- ─ Initialize AMIR leaderboard at race start ───────────────────
    do
  local names, times = {}, {}
      for i, pid in ipairs(lob.players) do
        names[i] = GetPlayerName(pid) or ""
        times[i] = 0
      end
      -- pad to exactly 9 entries
      for i = #names + 1, 9 do names[i], times[i] = "", 0 end
      -- show “1/totalLaps” instead of “0/totalLaps”
      local title = ("1/%d"):format(lob.laps)
      -- Initialize board according to viewMode
      local vm = (amirState[lobbyName] and amirState[lobbyName].vm) or (Config.Leaderboard.viewMode or "toggle")
      if vm == 'times' then vm = 'toggle' end -- coerce unsupported mode
      -- We always initialize with names to avoid flashing
      TriggerEvent("amir-leaderboard:setPlayerNames", title, names)
    end
    -- ───────────────────────────────────────────────────────────────
  end

  pendingChoices[lobbyName] = { total = #lob.players, received = 0, selected = {} }
  -- Immediately hide lobby UI for all members
  for _, pid in ipairs(lob.players) do
    TriggerClientEvent("speedway:hideLobbyWindow", pid)
  end
  -- Start a 30s vehicle selection countdown visible to players
  local deadline = GetGameTimer() + 30000
  CreateThread(function()
    while pendingChoices[lobbyName] do
      local now = GetGameTimer()
      local remaining = math.max(0, math.floor((deadline - now) / 1000))
      for _, pid in ipairs(lob.players) do
        TriggerClientEvent("speedway:vehicleSelectCountdown", pid, remaining)
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
          ServerNotify(pid, 'Speedway', locale("vehicle_select_timeout"), 'warning')
          TriggerClientEvent("speedway:kickedFromLobby", pid, lobbyName, "timeout")
          table.remove(lob.players, i)
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
      -- nobody left or nobody selected: cancel race
      pendingChoices[lobbyName] = nil
      lob.isStarted = false
      -- Ensure broadcast turns off if it was turned on earlier for this lobby
      TriggerClientEvent('rox_speedway:cam:broadcastOff', -1)
      for _, pid in ipairs(lob.players) do
        ServerNotify(pid, 'Speedway', locale("race_cancelled"), 'error')
      end
    end
  end)
  for _, pid in ipairs(lob.players) do
    TriggerClientEvent("speedway:chooseVehicle", pid, lobbyName, lob.raceClass)
  end
end)

--------------------------------------------------------------------------------
-- VEHICLE SELECTION RESPONSE
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:selectedVehicle", function(lobbyName, model)
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
    if not VALID_MODELS[model:lower()] then return end
    -- If race class has a specific vehicle list, validate model is in that class
    local cls = lob.raceClass
    if cls and Config.RaceClasses[cls] and Config.RaceClasses[cls].vehicles then
      local classAllowed = false
      for _, m in ipairs(Config.RaceClasses[cls].vehicles) do
        if m:lower() == model:lower() then classAllowed = true break end
      end
      if not classAllowed then return end
    end
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
RegisterNetEvent("speedway:updateProgress", function(lobbyName, dist)
  local src = source
  local lob = lobbies[lobbyName]
  if not lob or not lob.isStarted then return end
  -- Verify player is in this lobby
  if not table_contains(lob.players, src) then return end
  -- Validate and clamp distance
  dist = tonumber(dist)
  if not dist or dist ~= dist then return end -- reject non-number / NaN
  dist = math.max(0, math.min(dist, 15000))

  lob.progress[src] = dist

  local board = {}
  for _, pid in ipairs(lob.players) do
    table.insert(board, {
      id   = pid,
      lap  = lob.lapProgress[pid] or 0,
      dist = lob.progress[pid]    or 0
    })
  end

  table.sort(board, function(a, b)
    if a.lap ~= b.lap then
      return a.lap > b.lap
    end
    local acp = lob.checkpointProgress[a.id] or 0
    local bcp = lob.checkpointProgress[b.id] or 0
    if acp ~= bcp then
      return acp > bcp
    end
    return a.dist > b.dist
  end)

  -- Broadcast leader changes to all clients for spectator cameras
  do
    if #board > 0 then
      local leaderId = board[1].id
      lob.lastLeader = lob.lastLeader or -1
      if leaderId ~= lob.lastLeader then
        lob.lastLeader = leaderId
        TriggerClientEvent('speedway:leaderChanged', -1, lobbyName, leaderId)
        -- Inform feed module so it can request screenshots from the leader's client
        TriggerEvent('rox_speedway:feed:setLeader', lobbyName, leaderId)
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
    TriggerClientEvent("speedway:updatePosition", e.id, displayRank, #board)
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
        TriggerClientEvent("speedway:client:setGhosted", entry.id, true)
      elseif not isLapped and wasGhosted then
        lob.lappedGhost[entry.id] = nil
        TriggerClientEvent("speedway:client:setGhosted", entry.id, false)
      end
    end
  end

  -- Update AMIR leaderboard to reflect live positions and current lap/total
  if Config.Leaderboard and Config.Leaderboard.enabled then
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
        names[i] = GetPlayerName(pid) or ""
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
RegisterNetEvent("speedway:lapPassed", function(lobbyName)
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
  TriggerClientEvent("speedway:updateLap", src, displayLap, lob.laps)

  -- reset per-lap progress counters so sorting is fair at the new lap start
  lob.checkpointProgress[src] = 0
  lob.progress[src] = 0

  -- Leaderboard updates are handled continuously in updateProgress to reflect live positions

  -- if they’ve now completed the total number of laps…
  if curLap >= lob.laps then
    if not lob.finished[src] then
      lob.finished[src] = true

      -- warp them back, fade in/out
      TriggerClientEvent("speedway:client:finishTeleport", src, Config.outCoords)
      -- important “You finished!” toast
      TriggerClientEvent("speedway:youFinished", src)

      -- push their personal result
      local totalT, best = 0, math.huge
      for _, t in ipairs(lob.lapTimes[src]) do
        totalT, best = totalT + t, math.min(best, t)
      end
      if best == math.huge then best = 0 end

      TriggerClientEvent("speedway:finalRanking", src, {
        position  = table_count(lob.finished),
        totalTime = totalT,
        lapTimes  = lob.lapTimes[src],
        bestLap   = best
      })
    end

    -- once everyone’s finished, broadcast the podium and tear down
    local allFin = true
    for _, pid in ipairs(lob.players) do
      if not lob.finished[pid] then allFin = false break end
    end
    if allFin then
      -- Build expanded results with best lap, payouts, and "Most Improved"
      local results = {}
      local globalBestLap, bestLapPlayer = math.huge, nil
      for _, pid in ipairs(lob.players) do
        local sum, best = 0, math.huge
        for _, t in ipairs(lob.lapTimes[pid] or {}) do
          sum = sum + t
          if t < best then best = t end
        end
        if best < globalBestLap then
          globalBestLap = best
          bestLapPlayer = pid
        end
        if best == math.huge then best = 0 end
        results[#results+1] = {
          id = pid,
          name = GetPlayerName(pid) or ("Player " .. pid),
          time = sum,
          bestLap = best,
          lapTimes = lob.lapTimes[pid],
        }
      end
      table.sort(results, function(a,b) return a.time < b.time end)

      -- Add position, payout info, and best-lap flag
      for pos, entry in ipairs(results) do
        entry.position = pos
        entry.payout = 0
        if Config.Rewards and Config.Rewards.enabled then
          entry.payout = (Config.Rewards.payouts[pos] or 0)
              + (Config.Rewards.participationReward or 0)
          if entry.id == bestLapPlayer and Config.Rewards.bestLapBonus then
            entry.payout = entry.payout + Config.Rewards.bestLapBonus
            entry.isBestLap = true
          end
        end
        if Config.EntryFee and Config.EntryFee.enabled and lob.prizePool then
          local pct = Config.EntryFee.poolSplit[pos] or 0
          entry.payout = entry.payout + math.floor((lob.prizePool * pct) / 100)
        end
      end

      -- Calculate "Most Improved" (biggest gain from grid position to finish)
      local mostImprovedId, mostImprovedGain = nil, 0
      for _, entry in ipairs(results) do
        local gridPos = lob.gridOrder and lob.gridOrder[entry.id] or entry.position
        local gain = gridPos - entry.position  -- positive = gained positions
        if gain > mostImprovedGain then
          mostImprovedGain = gain
          mostImprovedId = entry.id
        end
        entry.gridPosition = gridPos
      end
      if mostImprovedGain <= 0 then mostImprovedId = nil end
      for _, entry in ipairs(results) do
        entry.isMostImproved = (entry.id == mostImprovedId)
      end

      -- Broadcast expanded results to all race participants
      for _, pid in ipairs(lob.players) do
        TriggerClientEvent("speedway:finalRanking", pid, {
          allResults = results,
          bestLapPlayer = bestLapPlayer,
          mostImprovedPlayer = mostImprovedId,
          track = lob.track,
        })
        TriggerClientEvent("speedway:client:destroyprops", pid)
      end

      -- Grant rewards (cash payouts, best lap bonus, vehicle prizes)
      GrantRewards(lob, results, lobbyName)

      -- Distribute entry fee prize pool
      DistributePrizePool(lob, results)

      -- Save persistent race stats for each player
      for pos, entry in ipairs(results) do
        -- Calculate total earnings for this player
        local totalEarnings = entry.payout or 0

        SaveRaceStats(entry.id, pos, lob.track, entry.bestLap or 0, totalEarnings)
      end

      -- Race fully concluded: switch jumbotron back to IDLE for everyone
      TriggerClientEvent('rox_speedway:cam:broadcastOff', -1)
      -- Reset leader tracking for this lobby
      lob.lastLeader = -1

      lobbies[lobbyName] = nil
      TriggerClientEvent("speedway:setLobbyState", -1, next(lobbies) ~= nil)

      -- Resume idle best-times display on the leaderboard
      if Config.Leaderboard and Config.Leaderboard.enabled then
        exports['rox_speedway']:ShowIdleLeaderboard()
      end
    end
  end
end)

--------------------------------------------------------------------------------
-- FINISH TELEPORT, FUEL, ETC.
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:finishTeleport", function(coords)
  TriggerClientEvent("speedway:client:finishTeleport", source, coords)
end)

RegisterNetEvent("speedway:client:fillFuel", function(netId)
  local v = NetworkGetEntityFromNetworkId(netId)
  if not v or v == 0 or not DoesEntityExist(v) then return end
  -- Server-safe: only use ox_fuel statebag here; most exports are client-only
  if GetResourceState("ox_fuel") == "started" then
    local st = Entity(v).state
    if st and st.set then st:set("fuel", 100.0, true) end
  end
  -- Ask clients to apply native fuel locally (driver will usually own the entity)
  TriggerClientEvent('rox_speedway:client:setFuel', -1, netId, 100.0)
end)

--------------------------------------------------------------------------------
-- SERVER-AUTHORITATIVE FUEL SYNC (called from client after pit stop)
--------------------------------------------------------------------------------
RegisterNetEvent("speedway:server:setFuel", function(netId, level)
  local src = source -- reserved if we later want to restrict
  if type(netId) ~= 'number' or type(level) ~= 'number' then return end
  if level < 0 then level = 0 end; if level > 100 then level = 100 end
  local v = NetworkGetEntityFromNetworkId(netId)
  if not v or v == 0 or not DoesEntityExist(v) then return end

  -- Native baseline cannot be called server-side; rely on client + fuel scripts
  -- Avoid calling client-only exports from server (causes 'No such export' spam)

  -- ox_fuel uses statebags
  if GetResourceState("ox_fuel") == "started" then
    local st = Entity(v).state
    if st and st.set then st:set("fuel", level + 0.0, true) end
  end

  if Config.DebugPrints then
    print(("[Speedway] Server fuel sync: netId=%s -> %.1f"):format(tostring(netId), level))
  end

  -- Reassert on clients too to overcome any late ticks from external scripts
  CreateThread(function()
    local tries = { 200, 800 }
    for _, waitMs in ipairs(tries) do
      Wait(waitMs)
      -- Reassert on clients; external scripts may tick and revert
      TriggerClientEvent('rox_speedway:client:setFuel', -1, netId, level + 0.0)
      if DoesEntityExist(v) and GetResourceState("ox_fuel") == "started" then
        local st = Entity(v).state
        if st and st.set then st:set("fuel", level + 0.0, true) end
      end
    end
  end)
end)

--------------------------------------------------------------------------------
-- LEADERBOARD: show idle best-times on resource start
--------------------------------------------------------------------------------
if Config.Leaderboard and Config.Leaderboard.enabled then
  CreateThread(function()
    -- Wait for sv_leaderboard.lua exports to be registered and DB to be ready
    Wait(3000)
    exports['rox_speedway']:ShowIdleLeaderboard()
  end)
end
