Payouts = {}

local function purseFor(pos, pid, bestLapPid, eco)
  local position = eco.payouts[pos] or 0
  local participation = eco.participationReward or 0
  local bestLap = (pid == bestLapPid and eco.bestLapBonus) or 0
  return position, participation, bestLap
end

function Payouts.PurseTotal(results, bestLapPid, eco)
  local sum = 0
  for pos, e in ipairs(results) do
    local a, b, c = purseFor(pos, e.id, bestLapPid, eco)
    sum = sum + a + b + c
  end
  return sum
end

---@return table payouts (pid -> parts), boolean purseCovered
function Payouts.Compute(results, bestLapPid, eco, pool, balance)
  local covered = (balance or 0) >= Payouts.PurseTotal(results, bestLapPid, eco)
  local out = {}
  for pos, e in ipairs(results) do
    local position, participation, bestLap = 0, 0, 0
    if covered then position, participation, bestLap = purseFor(pos, e.id, bestLapPid, eco) end
    local pct = eco.poolSplit[pos] or 0
    local poolPay = math.floor((pool or 0) * pct / 100)
    out[e.id] = { position = position, participation = participation, bestLap = bestLap, pool = poolPay,
                  total = position + participation + bestLap + poolPay }
  end
  return out, covered
end
