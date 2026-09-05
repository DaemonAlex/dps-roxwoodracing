-- Money in and out of the raceway. Every path goes through Banking so the ledger is the truth.
Rewards = {}

local function account() return Config.Job.name end
local function eco() return Config.Economy end

function Rewards.FeeAmount()
  local f = eco().entryFee
  return (f and f.enabled and f.amount) or 0
end

local function notify(pid, msgKey, ntype, ...)
  TriggerClientEvent('dps-roxwoodracing:client:notify', pid, Config.Job.label, Locale(msgKey, ...), ntype or 'inform')
end

function Rewards.ChargeEntryFee(pid, lobbyName)
  local amount = Rewards.FeeAmount()
  if amount <= 0 then return true end
  if not Bridge.Framework then return true end
  if Bridge.GetMoney(pid, eco().moneyType) < amount then
    notify(pid, 'entry_fee_insufficient', 'error', amount)
    return false
  end
  if not Bridge.RemoveMoney(pid, eco().moneyType, amount, 'roxwoodracing-entryfee') then return false end
  if not Banking.Deposit(account(), amount, 'Entry fee', ('Lobby %s'):format(tostring(lobbyName)), Bridge.GetPlayerName(pid)) then
    -- Bank refused: give the cash straight back rather than leave it in limbo
    Bridge.AddMoney(pid, eco().moneyType, amount, 'roxwoodracing-entryfee-bounce')
    print(('[dps-roxwoodracing] WARNING: society deposit failed for player %s; fee returned'):format(tostring(pid)))
    return false
  end
  notify(pid, 'entry_fee_charged', 'inform', amount)
  return true
end

function Rewards.RefundEntryFee(pid, lobbyName)
  local amount = Rewards.FeeAmount()
  if amount <= 0 or not Bridge.Framework then return end
  if not Bridge.GetPlayerIdentifier(pid) then return end -- offline: leave the fee in the account, nothing to pay to
  if not Banking.Withdraw(account(), amount, 'Entry fee refund', ('Lobby %s'):format(tostring(lobbyName)), Bridge.GetPlayerName(pid)) then
    return -- account drained meanwhile; nothing to refund from
  end
  Bridge.AddMoney(pid, eco().moneyType, amount, 'roxwoodracing-entryfee-refund')
  notify(pid, 'entry_fee_refunded', 'success', amount)
end

local function reasonFor(title) return 'roxwoodracing-' .. title:lower():gsub('%s', '-') end

local function payFromSource(pid, amount, title, message)
  if amount <= 0 then return true end
  if eco().purseSource == 'house' then
    Banking.LogOnly(account(), amount, title, message, account(), Bridge.GetPlayerName(pid))
    return Bridge.AddMoney(pid, eco().moneyType, amount, reasonFor(title))
  end
  if not Banking.Withdraw(account(), amount, title, message, Bridge.GetPlayerName(pid)) then return false end
  return Bridge.AddMoney(pid, eco().moneyType, amount, reasonFor(title))
end

---@param lob table lobby (uses prizePool, name)
---@param results table sorted results { {id=}, ... }
---@param bestLapPid number|nil
---@return table payouts, boolean purseCovered
function Rewards.Settle(lob, results, bestLapPid)
  if not Bridge.Framework then return {}, true end
  local balance = eco().purseSource == 'house' and math.huge or Banking.GetBalance(account())
  local allowPurse = #results >= (eco().minPlayersForPurse or 1)
  local payouts, covered, reason = Payouts.Compute(results, bestLapPid, eco(), lob.prizePool or 0, balance, allowPurse)
  local labelFor = { [1] = '1st', [2] = '2nd', [3] = '3rd' }
  for pos, entry in ipairs(results) do
    local pid, p = entry.id, payouts[entry.id]
    if Bridge.GetPlayerIdentifier(pid) then
      local msg = ('Lobby %s, %s'):format(tostring(lob.name), labelFor[pos] or (pos .. 'th'))
      payFromSource(pid, p.position, 'Podium purse', msg)
      payFromSource(pid, p.participation, 'Show-up bonus', msg)
      payFromSource(pid, p.bestLap, 'Fastest lap', msg)
      -- Pool money is the racers' own buy-ins parked in the account; always paid.
      if p.pool > 0 then
        if Banking.Withdraw(account(), p.pool, 'Prize pool', msg, Bridge.GetPlayerName(pid)) then
          Bridge.AddMoney(pid, eco().moneyType, p.pool, 'roxwoodracing-prizepool')
        end
      end
      local vehiclePrize = nil
      if pos == 1 and eco().vehiclePrize and covered then
        local okv, res = pcall(Garages.GiveVehicle, pid, eco().vehiclePrize, Rewards.UniquePlate('PRZ'))
        if okv and res then vehiclePrize = eco().vehiclePrize
        else print(('[dps-roxwoodracing] WARNING: prize car not delivered to %s: %s'):format(tostring(pid), tostring(res))) end
      end
      TriggerClientEvent('dps-roxwoodracing:client:rewardNotify', pid, {
        positionPayout = p.position, positionLabel = labelFor[pos] or (pos .. 'th'),
        participation = p.participation, bestLapBonus = p.bestLap, poolPayout = p.pool,
        vehiclePrize = vehiclePrize, totalPayout = p.total, purseCovered = covered, purseReason = reason,
      })
    end
  end
  return payouts, covered, reason
end

-- A plate no vehicle row already uses (checked, not assumed).
function Rewards.UniquePlate(prefix)
  for _ = 1, 20 do
    local plate = (prefix .. tostring(math.random(10000, 99999))):sub(1, 8)
    local table = Bridge.Framework == 'esx' and 'owned_vehicles' or 'player_vehicles'
    local n = MySQL.scalar.await(('SELECT COUNT(*) FROM %s WHERE TRIM(plate) = ?'):format(table), { plate })
    if (tonumber(n) or 0) == 0 then return plate end
  end
  return prefix .. tostring(GetGameTimer() % 100000)
end

CreateThread(function()
  Wait(1000)
  Banking.EnsureAccount(Config.Job.name, Config.Job.label)
end)
