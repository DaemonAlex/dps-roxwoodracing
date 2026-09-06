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

--- Index `back` points behind idx, wrapping.
function Practice.PrevIndex(idx, n, back)
  local j = idx - (back or 1)
  while j < 1 do j = j + n end
  return j
end

--- Where `other` sits relative to a car at `pos` facing `fwd` (2D): ahead (m along
--- heading, negative = behind) and lateral (m to the right, negative = left).
function Practice.Relative(pos, fwd, other)
  local dx, dy = other.x - pos.x, other.y - pos.y
  local ahead = dx * fwd.x + dy * fwd.y
  local lateral = dx * fwd.y - dy * fwd.x
  return ahead, lateral
end

--- Race decision against the nearest car ahead inside the awareness window.
--- Returns speed to run and the lateral aim offset (m, +right) to pass with.
function Practice.Decide(cruise, blockers, aware)
  local best
  for _, b in ipairs(blockers) do
    if b.ahead > 1.0 and b.ahead <= aware.range and math.abs(b.lateral) <= aware.lateral then
      if not best or b.ahead < best.ahead then best = b end
    end
  end
  if not best then return cruise, 0.0 end
  local speed = math.max(aware.minSpeed, cruise * (best.ahead / aware.range))
  local offset = 0.0
  if best.ahead <= (aware.passWithin or aware.range) then
    offset = best.lateral >= 0 and -aware.overtakeOffset or aware.overtakeOffset
  end
  return speed, offset
end

--- Point `offset` m to the right of the line at index idx (right of the direction of travel).
function Practice.OffsetPoint(pts, idx, n, offset)
  local a, b = pts[idx], pts[Practice.NextIndex(idx, n, 1)]
  local dx, dy = b.x - a.x, b.y - a.y
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.01 or offset == 0 then return a.x, a.y, a.z end
  local rx, ry = dy / len, -dx / len
  return a.x + rx * offset, a.y + ry * offset, a.z
end

--- Aim distance in points for a given speed: `seconds` of travel ahead, clamped.
function Practice.AimPoints(speed, seconds, spacing, minPts, maxPts)
  local pts = math.ceil((speed * seconds) / spacing)
  if pts < minPts then return minPts end
  if pts > maxPts then return maxPts end
  return pts
end

--- Circular forward distance from a to b on an n-point loop (0..n-1).
function Practice.Forward(a, b, n)
  local d = b - a
  if d < 0 then d = d + n end
  return d
end

--- Points ahead of `prog` before the line's heading has turned more than `maxTurnDeg`
--- from the heading at prog (uses pts[i].h). At least minPts, at most maxPts.
function Practice.AimByCurvature(pts, prog, n, minPts, maxPts, maxTurnDeg, closed)
  local h0 = pts[prog].h
  if not h0 then return maxPts end
  local count = 0
  for k = 1, maxPts do
    local j = prog + k
    if j > n then if closed then j = j - n else break end end
    local d = math.abs((pts[j].h or h0) - h0) % 360.0
    if d > 180.0 then d = 360.0 - d end
    if d > maxTurnDeg then break end
    count = k
  end
  if count < minPts then return minPts end
  return count
end
