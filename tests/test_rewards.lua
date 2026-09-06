local function setup(provider, balance)
  RESET_STUB()
  Config = { Job = { name = 'roxwoodracing', label = 'Roxwood Raceway' },
             Economy = { purseSource = 'society', entryFee = { enabled = true, amount = 1000 }, poolSplit = { [1] = 60, [2] = 30, [3] = 10 },
                         payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, moneyType = 'cash' } }
  local cash = { [1] = 2000, [2] = 50 }
  Bridge = { Framework = 'qbx',
    GetPlayerIdentifier = function(pid) return cash[pid] and ('CID' .. pid) or nil end,
    GetPlayerName = function(pid) return 'P' .. pid end,
    GetMoney = function(pid) return cash[pid] or 0 end,
    RemoveMoney = function(pid, _, amt) if (cash[pid] or 0) < amt then return false end cash[pid] = cash[pid] - amt return true end,
    AddMoney = function(pid, _, amt) cash[pid] = (cash[pid] or 0) + amt return true end,
    AddMoneyByIdentifier = function(cid, _, amt) cash[cid] = (cash[cid] or 0) + amt return true end }
  local society = balance
  Banking = { Provider = provider, GetBalance = function() return society end,
    Deposit = function(_, amt) society = society + amt return true end,
    Withdraw = function(_, amt) if society < amt then return false end society = society - amt return true end,
    LogOnly = function() end, EnsureAccount = function() return true end }
  Garages = { GiveVehicle = function() return true end }
  dofile('shared/payouts.lua'); dofile('server/rewards.lua')
  return cash, function() return society end
end

TEST('entry fee moves cash into the society account and refunds back', function()
  local cash, soc = setup('Renewed-Banking', 0)
  local ok, receipt = Rewards.ChargeEntryFee(1, 'L'); TRUTHY(ok); EQ(cash[1], 1000); EQ(soc(), 1000); EQ(receipt.amount, 1000); EQ(receipt.cid, 'CID1')
  FALSY(Rewards.ChargeEntryFee(2, 'L'), 'broke player')
  Config.Economy.entryFee.amount = 5000 -- a Director raises the fee after the charge: refund must still be what was paid
  TRUTHY(Rewards.RefundEntryFee(1, 'L', receipt)); EQ(cash[1], 2000); EQ(soc(), 0)
  FALSY(Rewards.RefundEntryFee(1, 'L', nil), 'no receipt, nothing to refund')
end)

TEST('Settle pays purse from society when covered', function()
  local cash, soc = setup('Renewed-Banking', 50000)
  local lob = { players = { 1, 2 }, prizePool = 2000, name = 'L' }
  local p, covered = Rewards.Settle(lob, { { id = 1 }, { id = 2 } }, 1)
  TRUTHY(covered)
  EQ(cash[1], 2000 + 5000 + 500 + 1000 + 1200)
  EQ(cash[2], 50 + 3000 + 500 + 600)
  EQ(soc(), 50000 - (5000 + 500 + 1000 + 1200) - (3000 + 500 + 600))
  EQ(STUB.clientEvents[1].name, 'dps-roxwoodracing:client:rewardNotify')
end)

TEST('Settle pays pool only when society is short', function()
  local cash, soc = setup('Renewed-Banking', 2000)
  local lob = { players = { 1, 2 }, prizePool = 2000, name = 'L' }
  local p, covered = Rewards.Settle(lob, { { id = 1 }, { id = 2 } }, 1)
  FALSY(covered)
  EQ(cash[1], 2000 + 1200); EQ(cash[2], 50 + 600); EQ(soc(), 200)
end)

TEST('house mode mints the purse and leaves the society untouched', function()
  local cash, soc = setup('Renewed-Banking', 0)
  Config.Economy.purseSource = 'house'
  local lob = { players = { 1 }, prizePool = 0, name = 'L' }
  local p, covered = Rewards.Settle(lob, { { id = 1 } }, 1)
  TRUTHY(covered); EQ(cash[1], 2000 + 5000 + 500 + 1000); EQ(soc(), 0)
end)

TEST('Settle reports what was actually paid when the account runs dry mid-payout', function()
  local cash, soc = setup('Renewed-Banking', 12000)          -- purse 5000+3000+1500+3*500+1000 = 12000, pool 3000 also parked here
  cash[3] = 10
  local lob = { players = { 1, 2, 3 }, prizePool = 3000, name = 'L' }
  local p, covered = Rewards.Settle(lob, { { id = 1 }, { id = 2 }, { id = 3 } }, 1)
  FALSY(covered, 'balance 12000 minus pool 3000 cannot cover a 12000 purse')
  EQ(p[1].position, 0); EQ(p[1].pool, 1800); EQ(cash[1], 2000 + 1800)
  EQ(p[3].pool, 300); EQ(cash[3], 10 + 300); EQ(soc(), 12000 - 3000)
end)

TEST('offline refund goes through AddMoneyByIdentifier', function()
  local cash, soc = setup('Renewed-Banking', 5000)
  TRUTHY(Rewards.RefundEntryFee(99, 'L', { cid = 'CID99', amount = 1000 }))
  EQ(cash['CID99'], 1000); EQ(soc(), 4000)
end)
