-- Practice mode: one host client per track runs that track's shared AI grid; every player
-- on the track laps against it. Lines cluster into tracks by location (Practice.Cluster),
-- so a second circuit gets its own zone, host, grid and lap clock. The server elects the
-- hosts, relays the running order to the sign (Roxwood only), records practice laps, and
-- sets each track's AI target lap from the best rolling average on that track.
PracticeServer = PracticeServer or {}
local present = {}      -- src -> { avg = ms|nil, track = id }
local host = {}         -- track id -> src
local targetLap = {}    -- track id -> ms
local lastBoard = 0
local lastLap = {}
local tracks = nil      -- cached Practice.Cluster over the stored lines

local function cfg() return Config.Practice.mode or {} end

local function allTracks()
  if tracks then return tracks end
  local lines = {}
  for _, r in ipairs(Lines.List()) do
    local pts = Lines.Get(r.name)
    if pts and #pts > 0 then lines[#lines + 1] = { name = r.name, pts = pts } end
  end
  if #lines == 0 then return nil end
  tracks = Practice.Cluster(lines, Config.Practice.trackJoinRadius)
  return tracks
end

--- The track the raceway sign belongs to: the one whose centre is nearest signCoords.
local function homeTrack()
  local ts = allTracks()
  if not ts then return nil end
  local sign = Config.Leaderboard and Config.Leaderboard.signCoords
  if not sign then return ts[1] end
  local best, bestD
  for _, t in ipairs(ts) do
    local d = Practice.Dist2D(t.centre, sign)
    if not bestD or d < bestD then best, bestD = t, d end
  end
  return best
end

local function setHost(track, src)
  if host[track] == src then return end
  if host[track] then TriggerClientEvent('dps-roxwoodracing:practice:host', host[track], false, track) end
  host[track] = src
  if src then TriggerClientEvent('dps-roxwoodracing:practice:host', src, true, track) end
  print(('[dps-roxwoodracing] practice host for %s: %s'):format(tostring(track), tostring(src)))
end

local function pickHost(track)
  local best
  for src, p in pairs(present) do
    if p.track == track and (not best or src < best) then best = src end
  end
  return best
end

local function broadcastTarget(track)
  local best
  for _, p in pairs(present) do
    if p.track == track and p.avg and (not best or p.avg < best) then best = p.avg end
  end
  if best ~= targetLap[track] then
    targetLap[track] = best
    for src, p in pairs(present) do
      if p.track == track then TriggerClientEvent('dps-roxwoodracing:practice:target', src, best) end
    end
  end
end

local function leave(src)
  local p = present[src]
  if not p then return end
  present[src] = nil
  if host[p.track] == src then setHost(p.track, pickHost(p.track)) end
  broadcastTarget(p.track)
end

RegisterNetEvent('dps-roxwoodracing:practice:enter', function(track)
  local src = source
  if type(track) ~= 'string' or #track > 40 then track = 'main' end
  if present[src] and present[src].track ~= track then leave(src) end
  local cid = Bridge.GetPlayerIdentifier(src)
  present[src] = { avg = cid and Stats.PracticeAvg and Stats.PracticeAvg(cid) or nil, track = track }
  if not host[track] then setHost(track, src) end
  TriggerClientEvent('dps-roxwoodracing:practice:target', src, targetLap[track])
  broadcastTarget(track)
end)

RegisterNetEvent('dps-roxwoodracing:practice:leave', function() leave(source) end)
AddEventHandler('playerDropped', function() leave(source) end)

-- A completed practice lap from a client on a track
RegisterNetEvent('dps-roxwoodracing:practice:lap', function(ms)
  local src = source
  local p = present[src]
  if not p then return end
  local c = cfg()
  if type(ms) ~= 'number' or ms < (c.minLapMs or 20000) or ms > (c.maxLapMs or 600000) then return end
  local now = os.time()
  if lastLap[src] and now - lastLap[src] < math.floor((c.minLapMs or 20000) / 1000) then return end
  lastLap[src] = now
  local cid = Bridge.GetPlayerIdentifier(src)
  if not cid then return end
  local best, avg, isBest, laps = Stats.SavePracticeLap(cid, math.floor(ms), c.keepLaps or 5)
  p.avg = avg
  TriggerClientEvent('dps-roxwoodracing:practice:lapResult', src, math.floor(ms), best, isBest, avg, laps)
  broadcastTarget(p.track)
end)

-- Running order from the raceway's host, onto everyone's sign (only while no race is live)
RegisterNetEvent('dps-roxwoodracing:practice:board', function(title, names)
  local src = source
  local home = homeTrack()
  if not home or src ~= host[home.id] or GlobalState.rwPracticeAllowed == false then return end
  local now = GetGameTimer()
  if now - lastBoard < 900 then return end
  if type(names) ~= 'table' or #names > 9 or type(title) ~= 'string' or #title > 6 then return end
  local clean = {}
  for i, n in ipairs(names) do
    if type(n) ~= 'string' or #n > 8 then return end
    clean[i] = n
  end
  lastBoard = now
  TriggerEvent('amir-leaderboard:setPlayerNames', title, clean)
end)

--- A lobby was created: warn everyone practising at the raceway.
function PracticeServer.RaceForming(lobbyName)
  local home = homeTrack()
  for src, p in pairs(present) do
    if not home or p.track == home.id then
      TriggerClientEvent('dps-roxwoodracing:practice:raceForming', src, lobbyName)
    end
  end
end

--- A race went live: move anyone on the raceway who is not in a live lobby to the paddock.
function PracticeServer.ClearTrack(inLobby)
  local e = homeTrack()
  if not e then return end
  local margin = cfg().clearMargin or 60.0
  for src, p in pairs(present) do
    if not inLobby[src] and p.track == e.id then
      local ped = GetPlayerPed(src)
      if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        local d = math.sqrt((pos.x - e.centre.x) ^ 2 + (pos.y - e.centre.y) ^ 2)
        if d <= e.radius + margin then
          TriggerClientEvent('dps-roxwoodracing:practice:cleared', src)
          TriggerClientEvent('dps-roxwoodracing:client:finishTeleport', src, Config.outCoords, true)
        end
      end
    end
  end
end

-- A new or re-recorded line may move or add a track.
RegisterNetEvent('dps-roxwoodracing:line:save', function() tracks = nil end)
