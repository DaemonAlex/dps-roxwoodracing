Ranking = {}

function Ranking.SortBoard(board, checkpointProgress)
  table.sort(board, function(a, b)
    if a.lap ~= b.lap then return a.lap > b.lap end
    local acp, bcp = checkpointProgress[a.id] or 0, checkpointProgress[b.id] or 0
    if acp ~= bcp then return acp > bcp end
    return a.dist > b.dist
  end)
  return board
end

function Ranking.BuildResults(players, lapTimes, gridOrder, nameOf)
  local results, globalBest, bestPid = {}, math.huge, nil
  for _, pid in ipairs(players) do
    local sum, best = 0, math.huge
    for _, t in ipairs(lapTimes[pid] or {}) do
      sum = sum + t
      if t < best then best = t end
    end
    if best < globalBest then globalBest, bestPid = best, pid end
    if best == math.huge then best = 0 end
    results[#results+1] = { id = pid, name = nameOf(pid), time = sum, bestLap = best, lapTimes = lapTimes[pid] or {} }
  end
  table.sort(results, function(a, b) return a.time < b.time end)
  local improvedPid, improvedGain = nil, 0
  for pos, e in ipairs(results) do
    e.position = pos
    e.gridPosition = (gridOrder and gridOrder[e.id]) or pos
    e.isBestLap = (e.id == bestPid)
    local gain = e.gridPosition - pos
    if gain > improvedGain then improvedGain, improvedPid = gain, e.id end
  end
  for _, e in ipairs(results) do e.isMostImproved = (e.id == improvedPid) end
  return results, bestPid, improvedPid
end
