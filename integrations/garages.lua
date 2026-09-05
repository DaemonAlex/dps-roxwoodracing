-- Prize-car delivery. With jg-advancedgarages the row carries garage_id (its column);
-- otherwise the stock qb/qbx 'garage' column.
Garages = {}
Garages.Provider = (GetResourceState('jg-advancedgarages') == 'started' or GetResourceState('jg-advancedgarages') == 'starting') and 'jg-advancedgarages' or 'none'
print(('[dps-roxwoodracing] garages: %s'):format(Garages.Provider))

function Garages.GiveVehicle(pid, model, plate)
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid then return false end
  local license = GetPlayerIdentifierByType(pid, 'license') or ''
  local garage = Config.Economy.prizeGarage or 'Roxwood Raceway'
  if Bridge.Framework == 'esx' then
    MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, stored) VALUES (?, ?, ?, 1)',
      { cid, plate, json.encode({ model = joaat(model), plate = plate }) })
    return true
  end
  if Garages.Provider == 'jg-advancedgarages' then
    MySQL.insert.await(
      'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage_id, in_garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1)',
      { license, cid, model, joaat(model), '{}', plate, garage })
  else
    MySQL.insert.await(
      'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
      { license, cid, model, joaat(model), '{}', plate, 'pillboxgarage' })
  end
  return true
end
