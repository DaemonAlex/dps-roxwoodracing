dofile('shared/ranking.lua')

TEST('SortBoard: lap beats checkpoint beats distance', function()
  local board = { { id = 1, lap = 0, dist = 900 }, { id = 2, lap = 1, dist = 10 }, { id = 3, lap = 0, dist = 100 } }
  Ranking.SortBoard(board, { [1] = 2, [3] = 3 })
  EQ(board[1].id, 2); EQ(board[2].id, 3); EQ(board[3].id, 1)
end)

TEST('BuildResults sorts by total, flags best lap and most improved', function()
  local lapTimes = { [1] = { 30000, 31000 }, [2] = { 29000, 33000 }, [3] = { 40000, 40000 } }
  local results, bestPid, improvedPid = Ranking.BuildResults({ 1, 2, 3 }, lapTimes, { [1] = 3, [2] = 1, [3] = 2 }, function(pid) return 'P' .. pid end)
  EQ(results[1].id, 1); EQ(results[1].time, 61000); EQ(results[1].position, 1); EQ(results[1].gridPosition, 3)
  EQ(bestPid, 2); TRUTHY(results[2].isBestLap); EQ(results[2].bestLap, 29000)
  EQ(improvedPid, 1); TRUTHY(results[1].isMostImproved); FALSY(results[2].isMostImproved)
  EQ(results[3].name, 'P3')
end)

TEST('BuildResults with no laps gives zero times and no badges', function()
  local results, bestPid, improvedPid = Ranking.BuildResults({ 5 }, {}, {}, function() return 'x' end)
  EQ(results[1].time, 0); EQ(results[1].bestLap, 0); EQ(bestPid, nil); EQ(improvedPid, nil)
end)
