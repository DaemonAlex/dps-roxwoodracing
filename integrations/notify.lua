-- Notifications. Detects once; every caller uses Notify().
local provider = 'print'
if GetResourceState('ox_lib') == 'started' or GetResourceState('ox_lib') == 'starting' then provider = 'ox_lib'
elseif GetResourceState('okokNotify') == 'started' then provider = 'okokNotify' end
print(('[dps-roxwoodracing] notify: %s'):format(provider))

local function mapType(t)
  if t == 'inform' or t == 'info' then return 'inform' end
  if t == 'warning' then return 'warning' end
  if t == 'error' then return 'error' end
  return 'success'
end

function Notify(title, description, ntype, duration)
  if provider == 'ox_lib' then
    lib.notify({ title = (title and title ~= '') and title or nil, description = description, type = mapType(ntype), duration = duration or 5000 })
  elseif provider == 'okokNotify' then
    exports.okokNotify:Alert(title or '', description or '', duration or 5000, mapType(ntype), false)
  else
    print(('[dps-roxwoodracing] %s: %s'):format(tostring(title), tostring(description)))
  end
end

RegisterNetEvent('dps-roxwoodracing:client:notify', function(title, description, ntype, duration)
  Notify(title, description, ntype, duration)
end)
