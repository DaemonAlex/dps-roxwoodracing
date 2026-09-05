-- Framework detection, shared by client and server. Order matters: qbx first.
Bridge = Bridge or {}

local function up(name)
  local st = GetResourceState(name)
  return st == 'started' or st == 'starting'
end

function Bridge.Detect()
  if Config.Framework then return Config.Framework end
  if up('qbx_core') then return 'qbx' end
  if up('qb-core') then return 'qb' end
  if up('es_extended') then return 'esx' end
  return nil
end

Bridge.Framework = Bridge.Detect()
print(('[dps-roxwoodracing] framework: %s'):format(Bridge.Framework or 'none'))
