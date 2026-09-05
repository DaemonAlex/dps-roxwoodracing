TEST('Staff.Can checks job and grade through the bridge', function()
  RESET_STUB(); Config = { Job = { name = 'roxwoodracing', grades = { marshal = 0, director = 2, owner = 3 } }, Economy = { payouts = {}, entryFee = {} } }
  Bridge = { HasJob = function(src, job, g) return src == 1 and job == 'roxwoodracing' and g <= 2 end }
  Race = {}; dofile('server/staff.lua')
  TRUTHY(Staff.Can(1, 'marshal')); TRUTHY(Staff.Can(1, 'director')); FALSY(Staff.Can(1, 'owner')); FALSY(Staff.Can(2, 'marshal'))
end)

TEST('SetSetting validates keys and applies onto Config.Economy', function()
  RESET_STUB(); Config = { Job = { name = 'roxwoodracing', grades = {} }, Economy = { payouts = { [1] = 5000 }, entryFee = { amount = 1000 }, participationReward = 500, bestLapBonus = 1000 } }
  Bridge = {}; Race = {}; dofile('server/staff.lua')
  TRUTHY(Staff.SetSetting('payout1', 7000)); EQ(Config.Economy.payouts[1], 7000)
  TRUTHY(Staff.SetSetting('entryfee', 250)); EQ(Config.Economy.entryFee.amount, 250)
  FALSY(Staff.SetSetting('hack', 1)); FALSY(Staff.SetSetting('payout1', -5))
  TRUTHY(STUB.queries[#STUB.queries].sql:find('dps_roxwoodracing_settings'))
end)

TEST('bossmenu server registers with qbx_management', function()
  RESET_STUB(); STUB.started = { qbx_management = true }
  Config = { Job = { name = 'roxwoodracing', bossCoords = vector3(0, 0, 0) } }
  local got
  STUB.exports = { qbx_management = { RegisterBossMenu = function(_, info) got = info end } }
  dofile('integrations/bossmenu.lua')
  EQ(BossMenu.Provider, 'qbx_management'); EQ(got.groupName, 'roxwoodracing'); EQ(got.type, 'job')
end)
