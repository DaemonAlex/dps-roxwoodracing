-- Vehicle keys. One provider, detected at boot; Keys.Give(veh, plate).
Keys = {}
local order = { 'wasabi_carlock', 'qs-vehiclekeys', 'Renewed-Vehiclekeys', 'qb-vehiclekeys' }
Keys.Provider = 'none'
for _, name in ipairs(order) do
  if GetResourceState(name) == 'started' or GetResourceState(name) == 'starting' then Keys.Provider = name break end
end
print(('[dps-roxwoodracing] keys: %s'):format(Keys.Provider))

function Keys.Give(veh, plate)
  local p = Keys.Provider
  if p == 'wasabi_carlock' then
    pcall(function() exports.wasabi_carlock:GiveKey(plate) end)
  elseif p == 'qs-vehiclekeys' then
    pcall(function() exports['qs-vehiclekeys']:GiveKeys(plate, nil, true) end)
  elseif p == 'Renewed-Vehiclekeys' then
    pcall(function() exports['Renewed-Vehiclekeys']:addKey(plate) end)
  elseif p == 'qb-vehiclekeys' then
    pcall(function() TriggerEvent('vehiclekeys:client:SetOwner', plate) end)
  end
  -- Always unlock as well; key scripts sometimes re-lock on spawn.
  SetVehicleDoorsLocked(veh, 1)
end

RegisterNetEvent('dps-roxwoodracing:client:giveKeys', function(netId, plate)
  local veh = NetworkGetEntityFromNetworkId(netId)
  if veh and veh ~= 0 and DoesEntityExist(veh) then Keys.Give(veh, plate or GetVehicleNumberPlateText(veh)) end
end)
