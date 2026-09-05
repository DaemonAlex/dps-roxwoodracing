TEST('ApplyTune sets indexed mods, resolves max, toggles turbo', function()
  RESET_STUB()
  Config = { Tune = { Race = { mods = { [11] = 'max', [12] = 1 }, toggles = { [18] = true } }, Stock = { mods = {}, toggles = {} } } }
  dofile('shared/tune.lua')
  local set, toggled, kit = {}, {}, nil
  function SetVehicleModKit(v, k) kit = k end
  function GetNumVehicleMods(v, slot) return slot == 11 and 4 or 2 end
  function SetVehicleMod(v, slot, idx) set[slot] = idx end
  function ToggleVehicleMod(v, slot, on) toggled[slot] = on end
  function DoesEntityExist() return true end
  function GetHashKey() return 0 end
  Customs = nil; dofile('client/customs.lua')
  Customs.ApplyTune(1, 'Race')
  EQ(kit, 0); EQ(set[11], 3); EQ(set[12], 1); TRUTHY(toggled[18])
  set = {}; Customs.ApplyTune(1, 'Stock'); EQ(next(set), nil)
end)
