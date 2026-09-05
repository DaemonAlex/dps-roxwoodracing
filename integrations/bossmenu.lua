-- Boss menu: qbx_management (native) or qb-bossmenu through the qbx bridge.
BossMenu = {}
local function up(name) local st = GetResourceState(name) return st == 'started' or st == 'starting' end
if IsDuplicityVersion() then
  BossMenu.Provider = up('qbx_management') and 'qbx_management' or (up('qb-bossmenu') and 'qb-bossmenu') or 'none'
  print(('[dps-roxwoodracing] bossmenu: %s'):format(BossMenu.Provider))
  function BossMenu.Register()
    if BossMenu.Provider == 'qbx_management' then
      pcall(function()
        exports.qbx_management:RegisterBossMenu({ groupName = Config.Job.name, type = 'job', coords = Config.Job.bossCoords, size = vec3(2.0, 2.0, 2.5) })
      end)
    end
  end
  CreateThread(function() Wait(2000); BossMenu.Register() end)
else
  BossMenu.Provider = up('qbx_management') and 'qbx_management' or 'none'
  function BossMenu.AddItem()
    if BossMenu.Provider ~= 'qbx_management' then return end
    pcall(function()
      exports.qbx_management:AddBossMenuItem({
        title = Locale('raceway_control'),
        description = 'Fees, purse, sign, end race',
        icon = 'flag-checkered',
        event = 'dps-roxwoodracing:client:openControl',
        args = { type = 'job', groupName = Config.Job.name },
      })
    end)
  end
  CreateThread(function() Wait(2000); BossMenu.AddItem() end)
end
