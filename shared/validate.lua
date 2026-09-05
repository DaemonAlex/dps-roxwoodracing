Validate = {}

---@return boolean ok, string|nil errKey, table clean
function Validate.CreateArgs(args, cfg)
  args = type(args) == 'table' and args or {}
  local clean = {}
  local name = args.name
  if type(name) ~= 'string' or #name < 1 or #name > 50 or name:find('[^%w_]') then return false, 'invalid_lobby_name', clean end
  clean.name = name
  if type(args.track) ~= 'string' or not cfg.Checkpoints[args.track] then return false, 'invalid_track', clean end
  clean.track = args.track
  local laps = tonumber(args.laps)
  if not laps or laps ~= math.floor(laps) or laps < 1 or laps > 10 then return false, 'invalid_laps', clean end
  clean.laps = laps
  local mode = args.mode or 'spec'
  if mode ~= 'spec' and mode ~= 'open' then return false, 'invalid_mode', clean end
  clean.mode = mode
  if mode == 'open' then
    local cls = args.class or 'Any'
    if type(cls) ~= 'string' or not cfg.OpenClasses[cls] then return false, 'invalid_class', clean end
    clean.class = cls
    clean.tune = 'Stock'
  else
    local cls = args.class or 'All'
    if type(cls) ~= 'string' or not (cfg.SpecClassKeys and cfg.SpecClassKeys[cls]) then return false, 'invalid_class', clean end
    clean.class = cls
    local tune = args.tune or 'Stock'
    if type(tune) ~= 'string' or not cfg.Tune[tune] then return false, 'invalid_tune', clean end
    clean.tune = tune
  end
  return true, nil, clean
end
