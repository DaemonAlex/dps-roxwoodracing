dofile('shared/payouts.lua')
local economy = { payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, poolSplit = { [1] = 60, [2] = 30, [3] = 10 } }

TEST('Payouts: allowPurse=false pays the pool only and says why', function()
  local p, covered, reason = Payouts.Compute({ { id = 1 } }, 1, economy, 1000, 1e9, false)
  FALSY(covered); EQ(reason, 'solo'); EQ(p[1].position, 0); EQ(p[1].pool, 600); EQ(p[1].total, 600)
  local _, c2, r2 = Payouts.Compute({ { id = 1 }, { id = 2 } }, 1, economy, 0, 0, true)
  FALSY(c2); EQ(r2, 'short')
  local _, c3, r3 = Payouts.Compute({ { id = 1 }, { id = 2 } }, 1, economy, 0, 1e9, true)
  TRUTHY(c3); EQ(r3, nil)
end)

TEST('Staff.SetSetting rejects values above the cap', function()
  RESET_STUB(); Config = { Job = { name = 'roxwoodracing', grades = {} }, Economy = { payouts = { [1] = 5000 }, entryFee = { amount = 1000 }, maxStaffSetting = 50000 } }
  Bridge = {}; Race = {}; dofile('server/staff.lua')
  FALSY(Staff.SetSetting('payout1', 50001)); TRUTHY(Staff.SetSetting('payout1', 50000)); EQ(Config.Economy.payouts[1], 50000)
end)

TEST('Lobbies.ClassForModel maps registry categories to class ids', function()
  RESET_STUB(); STUB.started = { qbx_core = true }
  Config = { SpecFallbackVehicles = {}, SpecPresets = {}, OpenClasses = { Super = { classes = { [7] = true } } } }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function() return 'C1' end }
  STUB.exports = { qbx_core = { GetVehiclesByName = function() return { krieger = { name = 'Krieger', category = 'super', hash = 12345 } } end } }
  dofile('server/lobbies.lua')
  EQ(Lobbies.ClassForModel(12345), 7); EQ(Lobbies.ClassForModel(999), nil)
end)

TEST('Rewards: solo race pays pool only; refund skipped for offline player', function()
  RESET_STUB()
  Config = { Job = { name = 'roxwoodracing', label = 'RR' }, Economy = { purseSource = 'society', entryFee = { enabled = true, amount = 1000 }, poolSplit = { [1] = 60, [2] = 30, [3] = 10 },
             payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, moneyType = 'cash', minPlayersForPurse = 2 } }
  local cash = { [1] = 0 }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function(pid) return cash[pid] and ('CID' .. pid) or nil end, GetPlayerName = function(pid) return 'P' .. pid end,
             GetMoney = function(pid) return cash[pid] or 0 end, RemoveMoney = function() return true end, AddMoney = function(pid, _, amt) cash[pid] = (cash[pid] or 0) + amt return true end }
  local society = 100000
  Banking = { Provider = 'x', GetBalance = function() return society end, Deposit = function(_, amt) society = society + amt return true end,
              Withdraw = function(_, amt) if society < amt then return false end society = society - amt return true end, LogOnly = function() end, EnsureAccount = function() return true end }
  Garages = { GiveVehicle = function() return true end }
  dofile('server/rewards.lua')
  local p, covered, reason = Rewards.Settle({ players = { 1 }, prizePool = 1000, name = 'L' }, { { id = 1 } }, 1)
  FALSY(covered); EQ(reason, 'solo'); EQ(cash[1], 600); EQ(society, 100000 - 600)
  Rewards.RefundEntryFee(99, 'L'); EQ(society, 100000 - 600, 'offline refund must not touch the account')
end)
