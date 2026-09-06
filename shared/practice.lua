-- Pure helpers for the AI practice cars; shared by the client and the tests.
Practice = Practice or {}

--- Evenly spread `cars` start positions around an n-point line (1-based index for car i).
function Practice.StartIndex(i, n, cars)
  return math.floor((i - 1) * n / cars) + 1
end

--- Index `step` points ahead of idx, wrapping. Second return: true when it wrapped.
function Practice.NextIndex(idx, n, step)
  local j = idx + (step or 1)
  if j > n then return j - n, true end
  return j, false
end

function Practice.Dist2D(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

--- Centre of the line and the farthest point's distance from it.
function Practice.Extent(pts)
  local sx, sy, sz, n = 0.0, 0.0, 0.0, #pts
  for i = 1, n do sx, sy, sz = sx + pts[i].x, sy + pts[i].y, sz + pts[i].z end
  local c = { x = sx / n, y = sy / n, z = sz / n }
  local r = 0.0
  for i = 1, n do local d = Practice.Dist2D(c, pts[i]); if d > r then r = d end end
  return c, r
end

--- Index of the line point closest (2D) to pos.
function Practice.NearestIndex(pts, pos)
  local best, bestD = 1, math.huge
  for i = 1, #pts do
    local d = Practice.Dist2D(pos, pts[i])
    if d < bestD then best, bestD = i, d end
  end
  return best
end
