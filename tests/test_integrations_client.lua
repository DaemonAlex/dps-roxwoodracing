TEST('Keys picks wasabi_carlock first and calls GiveKey(plate)', function()
  RESET_STUB(); STUB.started = { wasabi_carlock = true, ['qs-vehiclekeys'] = true }
  local got
  STUB.exports = { wasabi_carlock = { GiveKey = function(_, plate) got = plate end } }
  Config = { DebugPrints = false }
  function SetVehicleDoorsLocked() end
  dofile('integrations/keys.lua')
  EQ(Keys.Provider, 'wasabi_carlock')
  Keys.Give(42, 'SAMRIDER')
  EQ(got, 'SAMRIDER')
end)

TEST('Keys falls back to unlock-only when nothing is installed', function()
  RESET_STUB()
  local unlocked
  function SetVehicleDoorsLocked(veh, state) unlocked = { veh, state } end
  dofile('integrations/keys.lua')
  EQ(Keys.Provider, 'none')
  Keys.Give(42, 'X'); EQ(unlocked[2], 1)
end)

TEST('Fuel prefers the ox_fuel statebag', function()
  RESET_STUB(); STUB.started = { ox_fuel = true }
  local set
  Entity = function(veh) return { state = { set = function(_, k, v, r) set = { k, v, r } end } } end
  function SetVehicleFuelLevel() end
  function DoesEntityExist() return true end
  dofile('integrations/fuel.lua')
  EQ(Fuel.Provider, 'ox_fuel')
  Fuel.SetFull(9); EQ(set[1], 'fuel'); EQ(set[2], 100.0); EQ(set[3], true)
end)

TEST('Notify routes to ox_lib when present', function()
  RESET_STUB(); STUB.started = { ox_lib = true }
  local got
  lib.notify = function(t) got = t end
  dofile('integrations/notify.lua')
  Notify('T', 'D', 'success', 1234)
  EQ(got.title, 'T'); EQ(got.description, 'D'); EQ(got.type, 'success'); EQ(got.duration, 1234)
end)
