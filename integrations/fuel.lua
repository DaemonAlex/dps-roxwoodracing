-- Fuel. ox_fuel uses the entity statebag; others use their export; natives last.
Fuel = {}
Fuel.Provider = 'native'
local exportsByName = {
  ['LegacyFuel']      = function(veh, lvl) exports['LegacyFuel']:SetFuel(veh, lvl) end,
  ['cdn-fuel']        = function(veh, lvl) exports['cdn-fuel']:SetFuel(veh, lvl) end,
  ['okokGasStation']  = function(veh, lvl) exports['okokGasStation']:SetFuel(veh, lvl) end,
  ['qs-fuelstations'] = function(veh, lvl) exports['qs-fuelstations']:SetFuel(veh, lvl) end,
}
if GetResourceState('ox_fuel') == 'started' or GetResourceState('ox_fuel') == 'starting' then
  Fuel.Provider = 'ox_fuel'
else
  for name in pairs(exportsByName) do
    if GetResourceState(name) == 'started' then Fuel.Provider = name break end
  end
end
print(('[dps-roxwoodracing] fuel: %s'):format(Fuel.Provider))

function Fuel.Set(veh, level)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  level = math.max(0.0, math.min(100.0, level + 0.0))
  if Fuel.Provider == 'ox_fuel' then
    Entity(veh).state:set('fuel', level, true)
  elseif exportsByName[Fuel.Provider] then
    pcall(exportsByName[Fuel.Provider], veh, level)
  end
  pcall(SetVehicleFuelLevel, veh, level)
end

function Fuel.SetFull(veh) Fuel.Set(veh, 100.0) end

RegisterNetEvent('dps-roxwoodracing:client:setFuel', function(netId, level)
  Fuel.Set(NetworkGetEntityFromNetworkId(netId), level)
end)
RegisterNetEvent('dps-roxwoodracing:client:fillFuel', function(netId)
  Fuel.SetFull(NetworkGetEntityFromNetworkId(netId))
end)
