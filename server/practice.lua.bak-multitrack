-- Practice mode: one host client runs the shared AI grid; every player on the track laps
-- against it. The server elects the host, relays the running order to the sign, records
-- practice laps, and sets the AI target lap from the best rolling average on the track.
PracticeServer = PracticeServer or {}
local present = {}      -- src -> { avg = ms|nil }
local host = nil
local targetLap = nil
local lastBoard = 0
local lastLap = {}
local extent = nil

local function cfg() return Config.Practice.mode or {} end

local function trackExtent()
  if extent then return extent end
  local name = (Config.Practice.ai and Config.Practice.ai.lineNames and Config.Practice.ai.lineNames[1]) or 'main'
  local pts = Lines.Get(name)
  if not pts then return nil end
  local c, r = Practice.Extent(pts)
  extent = { x = c.x, y = c.y, z = c.z, r = r }
  return extent
end

local function setHost(src)
  if host == src then return end
  if host then TriggerClientEvent('dps-roxwoodracing:practice:host', host, false) end
  host = src
  if src then TriggerClientEvent('dps-roxwoodracing:practice:host', src, true) end
  print(('[dps-roxwoodracing] practice host: %s'):format(tostring(src)))
end

local function pickHost()
  local best
  for src in pairs(present) do if not best or src < best then best = src end end
  return best
end

local function broadcastTarget()
  local best
  for _, p in pairs(present) do
    if p.avg and (not best or p.avg < best) then best = p.avg end
  end
  if best ~= targetLap then
    targetLap = best
    TriggerClientEvent('dps-roxwoodracing:practice:target', -1, targetLap)
  end
end

RegisterNetEvent('dps-roxwoodracing:practice:enter', function()
  local src = source
  local cid = Bridge.GetPlayerIdentifier(src)
  present[src] = { avg = cid and Stats.PracticeAvg and Stats.PracticeAvg(cid) or nil }
  if not host then setHost(src) end
  TriggerClientEvent('dps-roxwoodracing:practice:target', src, targetLap)
  broadcastTarget()
end)

local function leave(src)
  if not present[src] then return end
  present[src] = nil
  if host == src then setHost(pickHost()) end
  broadcastTarget()
end
RegisterNetEvent('dps-roxwoodracing:practice:leave', function() leave(source) end)
AddEventHandler('playerDropped', function() leave(source) end)

-- A completed practice lap from a client on the track
RegisterNetEvent('dps-roxwoodracing:practice:lap', function(ms)
  local src = source
  if not present[src] then return end
  local c = cfg()
  if type(ms) ~= 'number' or ms < (c.minLapMs or 20000) or ms > (c.maxLapMs or 600000) then return end
  local now = os.time()
  if lastLap[src] and now - lastLap[src] < math.floor((c.minLapMs or 20000) / 1000) then return end
  lastLap[src] = now
  local cid = Bridge.GetPlayerIdentifier(src)
  if not cid then return end
  local best, avg, isBest, laps = Stats.SavePracticeLap(cid, math.floor(ms), c.keepLaps or 5)
  present[src].avg = avg
  TriggerClientEvent('dps-roxwoodracing:practice:lapResult', src, math.floor(ms), best, isBest, avg, laps)
  broadcastTarget()
end)

-- Running order from the host, onto everyone's sign (only while no race is live)
RegisterNetEvent('dps-roxwoodracing:practice:board', function(title, names)
  local src = source
  if src ~= host or GlobalState.rwPracticeAllowed == false then return end
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

--- A lobby was created: warn everyone practising.
function PracticeServer.RaceForming(lobbyName)
  for src in pairs(present) do
    TriggerClientEvent('dps-roxwoodracing:practice:raceForming', src, lobbyName)
  end
end

--- A race went live: move anyone on the track who is not in a live lobby to the paddock.
function PracticeServer.ClearTrack(inLobby)
  local e = trackExtent()
  if not e then return end
  local margin = cfg().clearMargin or 60.0
  for src in pairs(present) do
    if not inLobby[src] then
      local ped = GetPlayerPed(src)
      if ped and ped ~= 0 then
        local pos = GetEntityCoords(ped)
        local d = math.sqrt((pos.x - e.x) ^ 2 + (pos.y - e.y) ^ 2)
        if d <= e.r + margin then
          TriggerClientEvent('dps-roxwoodracing:practice:cleared', src)
          TriggerClientEvent('dps-roxwoodracing:client:finishTeleport', src, Config.outCoords, true)
        end
      end
    end
  end
end

-- After the idle board resumes, the host re-sends the practice order on its own.
RegisterNetEvent('dps-roxwoodracing:line:save', function() extent = nil end)
