Tune = {}
function Tune.ModsFor(preset, cfg)
  local t = cfg.Tune and cfg.Tune[preset]
  if not t then return { mods = {}, toggles = {} } end
  return { mods = t.mods or {}, toggles = t.toggles or {} }
end
