Staff = {}
local SETTINGS = 'dps_roxwoodracing_settings'
local keys = {
  payout1 = function(v) Config.Economy.payouts[1] = v end,
  payout2 = function(v) Config.Economy.payouts[2] = v end,
  payout3 = function(v) Config.Economy.payouts[3] = v end,
  showup  = function(v) Config.Economy.participationReward = v end,
  bestlap = function(v) Config.Economy.bestLapBonus = v end,
  entryfee = function(v) Config.Economy.entryFee.amount = v; Config.Economy.entryFee.enabled = v > 0 end,
}

function Staff.Can(src, gradeKey)
  local g = Config.Job.grades[gradeKey] or 0
  return Bridge.HasJob and Bridge.HasJob(src, Config.Job.name, g) or false
end

function Staff.SetSetting(k, v)
  v = tonumber(v)
  if not keys[k] or not v or v < 0 or v ~= math.floor(v) then return false end
  keys[k](v)
  MySQL.query.await(('INSERT INTO %s (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = ?'):format(SETTINGS), { k, tostring(v), tostring(v) })
  return true
end

function Staff.LoadSettings()
  MySQL.query.await(('CREATE TABLE IF NOT EXISTS %s (k VARCHAR(40) NOT NULL PRIMARY KEY, v VARCHAR(200))'):format(SETTINGS))
  local rows = MySQL.query.await(('SELECT k, v FROM %s'):format(SETTINGS)) or {}
  for _, r in ipairs(rows) do if keys[r.k] and tonumber(r.v) then keys[r.k](tonumber(r.v)) end end
  print(('[dps-roxwoodracing] staff settings loaded: %d overrides'):format(#rows))
end

function Staff.Snapshot()
  local e = Config.Economy
  return { payout1 = e.payouts[1], payout2 = e.payouts[2], payout3 = e.payouts[3], showup = e.participationReward,
           bestlap = e.bestLapBonus, entryfee = e.entryFee.amount, purseSource = e.purseSource,
           balance = Banking and Banking.GetBalance(Config.Job.name) or 0, lobbies = Race.ListLobbies and Race.ListLobbies() or {} }
end

lib.callback.register('dps-roxwoodracing:staff:snapshot', function(src)
  if not Staff.Can(src, 'marshal') then return nil end
  return Staff.Snapshot()
end)

RegisterNetEvent('dps-roxwoodracing:staff:action', function(action, payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}
  local function deny() TriggerClientEvent('dps-roxwoodracing:client:notify', src, Config.Job.label, Locale('staff_only'), 'error') end
  if action == 'endRace' then
    if not Staff.Can(src, 'marshal') then return deny() end
    Race.EndLobby(payload.lobby, 'staff')
  elseif action == 'clearProps' then
    if not Staff.Can(src, 'marshal') then return deny() end
    TriggerClientEvent('dps-roxwoodracing:client:destroyprops', -1)
  elseif action == 'signMode' then
    if not Staff.Can(src, 'marshal') then return deny() end
    Race.SetSignMode(payload.lobby, payload.mode)
  elseif action == 'setSetting' then
    if not Staff.Can(src, 'director') then return deny() end
    if not Staff.SetSetting(payload.key, payload.value) then
      TriggerClientEvent('dps-roxwoodracing:client:notify', src, Config.Job.label, 'Invalid value.', 'error')
    end
  end
end)

CreateThread(function() Wait(1500); Staff.LoadSettings() end)
