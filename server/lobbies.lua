-- Spec catalogue (any registered car, grouped by class) and Open-mode ownership checks.
Lobbies = {}
Lobbies._catalogue = nil

local skipCategories = { emergency = true, service = true, military = true, utility = true, commercial = true,
                         industrial = true, trailers = true, boats = true, helicopters = true, planes = true, cycles = true, trains = true }
local categoryLabel = { compacts = 'Compacts', sedans = 'Sedans', suvs = 'SUVs', coupes = 'Coupes', muscle = 'Muscle',
                        sportsclassics = 'Sports Classics', sports = 'Sports', super = 'Super', motorcycles = 'Motorcycles',
                        offroad = 'Off-road', vans = 'Vans', pickups = 'Pickups', openwheel = 'Open Wheel', race = 'Race' }

local function registry()
  if Bridge.Framework == 'qbx' or Bridge.Framework == 'qb' then
    local ok, v = pcall(function()
      local res = Bridge.Framework == 'qbx' and 'qbx_core' or 'qb-core'
      return exports[res]:GetVehiclesByName()
    end)
    if ok and type(v) == 'table' and next(v) then return v end
  end
  return nil
end

function Lobbies.SpecCatalogue()
  if Lobbies._catalogue then return Lobbies._catalogue end
  local classes, order = { All = { label = 'Open class (any car)', vehicles = {} } }, { 'All' }
  local reg = registry()
  if reg then
    local models = {}
    for model, v in pairs(reg) do models[#models+1] = { model = model, label = v.name or model, category = (v.category or 'other'):lower() } end
    table.sort(models, function(a, b) return a.label < b.label end)
    for _, v in ipairs(models) do
      if not skipCategories[v.category] then
        local key = categoryLabel[v.category] and categoryLabel[v.category]:gsub('[^%w]', '') or 'Other'
        if not classes[key] then classes[key] = { label = categoryLabel[v.category] or 'Other', vehicles = {} }; order[#order+1] = key end
        classes[key].vehicles[#classes[key].vehicles+1] = { model = v.model, label = v.label }
        classes.All.vehicles[#classes.All.vehicles+1] = { model = v.model, label = v.label }
      end
    end
  else
    print('[dps-roxwoodracing] WARNING: no vehicle registry; spec menu uses Config.SpecFallbackVehicles only')
  end
  -- Base-game models are not in the addon registry but always exist client-side: merge the
  -- curated vanilla list under its own group so presets (Super, Tuner, ...) can resolve.
  do
    local known = {}
    for _, v in ipairs(classes.All.vehicles) do known[v.model:lower()] = true end
    local vanilla = {}
    for _, v in ipairs(Config.SpecFallbackVehicles or {}) do
      if not known[v.model:lower()] then
        known[v.model:lower()] = true
        vanilla[#vanilla+1] = { model = v.model, label = v.label }
        classes.All.vehicles[#classes.All.vehicles+1] = { model = v.model, label = v.label }
      end
    end
    if #vanilla > 0 then classes.Vanilla = { label = 'Vanilla (base game)', vehicles = vanilla }; order[#order+1] = 'Vanilla' end
  end
  -- Named presets from config (only models the registry knows, or all when no registry)
  local known = {}
  for _, v in ipairs(classes.All.vehicles) do known[v.model:lower()] = v end
  for key, preset in pairs(Config.SpecPresets or {}) do
    if preset.vehicles then
      local list = {}
      for _, m in ipairs(preset.vehicles) do
        local v = known[m:lower()]
        if v then list[#list+1] = v end
      end
      if #list > 0 then
        local k = 'Preset' .. key
        classes[k] = { label = preset.label or key, vehicles = list }; order[#order+1] = k
      else
        print(('[dps-roxwoodracing] preset %s has no registered vehicles; skipped'):format(key))
      end
    end
  end
  Config.SpecClassKeys = {}
  for k in pairs(classes) do Config.SpecClassKeys[k] = true end
  Lobbies._catalogue = { classes = classes, order = order }
  print(('[dps-roxwoodracing] spec catalogue: %d vehicles in %d groups'):format(#classes.All.vehicles, #order))
  return Lobbies._catalogue
end

function Lobbies.IsModelAllowed(classKey, model)
  local cat = Lobbies.SpecCatalogue()
  local cls = cat.classes[classKey]
  if not cls or type(model) ~= 'string' then return false end
  local m = model:lower()
  for _, v in ipairs(cls.vehicles) do if v.model:lower() == m then return true end end
  return false
end

function Lobbies.OpenClassAllows(classKey, vehicleClassId)
  local oc = Config.OpenClasses[classKey]
  if not oc then return false end
  if not oc.classes then return true end
  return oc.classes[vehicleClassId] == true
end

function Lobbies.VerifyOwnedVehicle(pid, plate)
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid or type(plate) ~= 'string' then return false end
  plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
  local n
  if Bridge.Framework == 'esx' then
    n = MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ? AND owner = ?', { plate, cid })
  else
    n = MySQL.scalar.await('SELECT COUNT(*) FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, cid })
  end
  return (tonumber(n) or 0) > 0
end

lib.callback.register('dps-roxwoodracing:getSpecCatalogue', function() return Lobbies.SpecCatalogue() end)
lib.callback.register('dps-roxwoodracing:getOpenClasses', function()
  local out = {}
  for k, v in pairs(Config.OpenClasses) do out[#out+1] = { value = k, label = v.label } end
  table.sort(out, function(a, b) if a.value == 'Any' then return true elseif b.value == 'Any' then return false end return a.label < b.label end)
  return out
end)

CreateThread(function() Wait(500); Lobbies.SpecCatalogue() end)
