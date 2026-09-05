local function load()
  RESET_STUB(); STUB.started = { qbx_core = true }
  Config = { SpecFallbackVehicles = { { model = 'sultan3', label = 'Sultan RS Classic' } },
             SpecPresets = { Super = { label = 'Super Cars', description = '', vehicles = { 'krieger' } }, All = { label = 'x', vehicles = nil } },
             SpecClassLabels = { [6] = 'Sports', [7] = 'Super' }, OpenClasses = { Any = { classes = nil }, Super = { classes = { [7] = true } } } }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function() return 'C1' end }
  STUB.exports = { qbx_core = { GetVehiclesByName = function() return {
    krieger = { name = 'Krieger', category = 'super', model = 'krieger' },
    sultan3 = { name = 'Sultan RS Classic', category = 'sports', model = 'sultan3' },
    ambulance = { name = 'Ambulance', category = 'emergency', model = 'ambulance' },
  } end } }
  dofile('server/lobbies.lua')
end

TEST('SpecCatalogue groups registry vehicles by category and skips emergency/service', function()
  load()
  local cat = Lobbies.SpecCatalogue()
  TRUTHY(cat.classes.All); EQ(#cat.classes.All.vehicles, 2, 'sultan3 is in both registry and fallback: not duplicated')
  EQ(cat.classes.Super.vehicles[1].model, 'krieger')
  TRUTHY(Config.SpecClassKeys.All); TRUTHY(Config.SpecClassKeys.Sports); TRUTHY(Config.SpecClassKeys.Super); TRUTHY(Config.SpecClassKeys.PresetSuper)
  TRUTHY(Lobbies.IsModelAllowed('All', 'sultan3')); TRUTHY(Lobbies.IsModelAllowed('Super', 'krieger')); FALSY(Lobbies.IsModelAllowed('Super', 'sultan3'))
  FALSY(Lobbies.IsModelAllowed('All', 'ambulance'))
end)

TEST('SpecCatalogue falls back to the vanilla list without a registry', function()
  load(); STUB.exports = {}; Lobbies._catalogue = nil
  local cat = Lobbies.SpecCatalogue()
  EQ(#cat.classes.All.vehicles, 1); EQ(cat.classes.All.vehicles[1].model, 'sultan3'); TRUTHY(cat.classes.Vanilla)
end)

TEST('vanilla models missing from the registry join the catalogue and presets resolve', function()
  load(); Lobbies._catalogue = nil
  Config.SpecFallbackVehicles = { { model = 'sultan3', label = 'Sultan RS Classic' }, { model = 'krieger', label = 'Krieger' }, { model = 'zr350', label = 'ZR350' } }
  Config.SpecPresets = { Tuner = { label = 'Tuners', vehicles = { 'zr350' } } }
  local cat = Lobbies.SpecCatalogue()
  EQ(#cat.classes.All.vehicles, 3); EQ(#cat.classes.Vanilla.vehicles, 1); EQ(cat.classes.Vanilla.vehicles[1].model, 'zr350')
  TRUTHY(cat.classes.PresetTuner); EQ(cat.classes.PresetTuner.vehicles[1].model, 'zr350')
end)

TEST('VerifyOwnedVehicle checks the plate against the citizenid', function()
  load(); STUB.scalar = 1
  TRUTHY(Lobbies.VerifyOwnedVehicle(7, 'SAM123 '))
  EQ(STUB.queries[#STUB.queries].params[1], 'SAM123'); EQ(STUB.queries[#STUB.queries].params[2], 'C1')
  STUB.scalar = 0; FALSY(Lobbies.VerifyOwnedVehicle(7, 'NOPE'))
end)

TEST('OpenClassAllows uses GetVehicleClass ids', function()
  load()
  TRUTHY(Lobbies.OpenClassAllows('Any', 3)); TRUTHY(Lobbies.OpenClassAllows('Super', 7)); FALSY(Lobbies.OpenClassAllows('Super', 6))
end)
