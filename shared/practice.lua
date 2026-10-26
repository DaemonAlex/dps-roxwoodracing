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

--- Group lines into tracks by location: a line joins the first track whose centre lies within
--- joinRadius of the line's own centre, else it starts a new track. Each track carries the
--- merged centre and reach of its lines, its lines sorted by name (a base line sorts before
--- its "#n" variants), and an id: the base name of its first line. Tracks come back sorted by id.
function Practice.Cluster(lines, joinRadius)
  joinRadius = joinRadius or 1500.0
  local tracks = {}
  for _, L in ipairs(lines) do
    local c = Practice.Extent(L.pts)
    local home
    for _, t in ipairs(tracks) do
      if Practice.Dist2D(c, t.centre) <= joinRadius then home = t break end
    end
    if not home then home = { centre = c, lines = {} }; tracks[#tracks + 1] = home end
    home.lines[#home.lines + 1] = L
  end
  for _, t in ipairs(tracks) do
    local merged = {}
    for _, L in ipairs(t.lines) do for _, p in ipairs(L.pts) do merged[#merged + 1] = p end end
    t.centre, t.radius = Practice.Extent(merged)
    table.sort(t.lines, function(a, b) return a.name < b.name end)
    t.id = (t.lines[1].name:gsub('#.*$', ''))
  end
  table.sort(tracks, function(a, b) return a.id < b.id end)
  return tracks
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

--- Which way the line bends over the next `k` points: +1 right, -1 left, 0 straight.
--- GTA headings grow counter-clockwise, so a right turn is a falling heading.
function Practice.BendAhead(pts, prog, n, k, closed, deadband)
  local h0 = pts[prog].h
  local j = prog + (k or 6)
  if j > n then if closed then j = j - n else j = n end end
  local h1 = pts[j].h
  if not h0 or not h1 then return 0 end
  local d = (h1 - h0 + 540.0) % 360.0 - 180.0
  local db = deadband or 6.0
  if d < -db then return 1 elseif d > db then return -1 end
  return 0
end

--- Racecraft against the cars around this one. `others` = { ahead (m, negative = behind),
--- lateral (m, +right) }. `ctx.bend` = +1/-1/0 for the next corner. Returns speed and the
--- lateral aim offset (m, +right). Attack the inside of the next corner, slipstream and
--- brake late behind a car, lift only when right on its tail, defend the attacker's side
--- on a straight.
function Practice.Decide(cruise, others, aware, ctx)
  ctx = ctx or {}
  local front, back
  for _, b in ipairs(others) do
    if b.ahead > 1.0 and b.ahead <= aware.range and math.abs(b.lateral) <= aware.lateral then
      if not front or b.ahead < front.ahead then front = b end
    elseif b.ahead < -1.0 and -b.ahead <= (aware.defendRange or 18.0) and math.abs(b.lateral) <= aware.lateral then
      if not back or b.ahead > back.ahead then back = b end
    end
  end
  local speed, offset = cruise, 0.0
  if front then
    if front.ahead <= (aware.passWithin or aware.range) then
      if (ctx.bend or 0) ~= 0 then
        offset = ctx.bend * aware.overtakeOffset                       -- inside of the next corner
      else
        offset = front.lateral >= 0 and -aware.overtakeOffset or aware.overtakeOffset   -- free side
      end
    end
    if front.ahead <= (aware.slipRange or 0) and math.abs(front.lateral) <= (aware.slipLateral or 3.0) then
      speed = cruise * (aware.slipBonus or 1.0)                         -- tow along the straight
    end
    if front.ahead <= (aware.lateBrakeRange or 0) then
      speed = speed * (aware.lateBrakeFactor or 1.0)                     -- brake later than the profile says
    end
    if front.ahead <= (aware.closeGap or 10.0) and math.abs(front.lateral) <= (aware.closeLateral or 2.5) then
      speed = math.min(speed, math.max(aware.minSpeed, cruise * (aware.closeFactor or 0.8)))
    end
  elseif back and (ctx.bend or 0) == 0 then
    offset = (back.lateral >= 0 and 1 or -1) * (aware.defendOffset or 2.5)   -- close the door
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

--- Distance (2D) from point p to the segment a-b.
function Practice.DistToSegment(p, a, b)
  local vx, vy = b.x - a.x, b.y - a.y
  local wx, wy = p.x - a.x, p.y - a.y
  local len2 = vx * vx + vy * vy
  local t = 0.0
  if len2 > 0.0001 then t = math.max(0.0, math.min(1.0, (wx * vx + wy * vy) / len2)) end
  local cx, cy = a.x + t * vx, a.y + t * vy
  return math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
end

--- Largest aim (points ahead of prog, minPts..maxPts) such that the straight line from
--- `pos` to the aim point passes within `maxCut` metres of every line point between.
--- This is what stops corner cutting: the aim shortens exactly where the line bends away.
function Practice.AimByChord(pts, pos, prog, n, minPts, maxPts, maxCut, closed)
  local best = minPts
  for k = minPts, maxPts do
    local j = prog + k
    if j > n then if closed then j = j - n else break end end
    local ok = true
    for m = 1, k - 1 do
      local i = prog + m
      if i > n then i = i - n end
      if Practice.DistToSegment(pts[i], pos, pts[j]) > maxCut then ok = false break end
    end
    if not ok then break end
    best = k
  end
  return best
end

--- Sign-friendly name: first word, upper-case alphanumerics, at most 5 characters.
function Practice.ShortName(name)
  name = tostring(name or ''):match('^%s*(%S+)') or ''
  name = name:upper():gsub('[^A-Z0-9]', '')
  if #name == 0 then name = 'PLYR' end
  return name:sub(1, 5)
end

--- Rolling average of the last `keep` laps. Returns the new list and its average (ms).
function Practice.RollingAvg(recent, ms, keep)
  local out = {}
  for _, v in ipairs(recent or {}) do out[#out + 1] = v end
  if ms then out[#out + 1] = ms end
  while #out > (keep or 5) do table.remove(out, 1) end
  if #out == 0 then return out, nil end
  local sum = 0
  for _, v in ipairs(out) do sum = sum + v end
  return out, math.floor(sum / #out)
end

--- AI pace multiplier so the grid laps a little quicker than the target lap.
--- aiLapMs was measured while running at aiMult (lap time scales ~1/mult).
function Practice.PaceMult(aiLapMs, aiMult, targetLapMs, margin, minMult, maxMult)
  if not aiLapMs or aiLapMs <= 0 or not targetLapMs or targetLapMs <= 0 then return nil end
  local baseLap = aiLapMs * (aiMult or 1.0)          -- lap at full pace
  local wanted = targetLapMs * (1 - (margin or 0.03))
  local mult = baseLap / wanted
  if mult < (minMult or 0.75) then mult = minMult or 0.75 end
  if mult > (maxMult or 1.05) then mult = maxMult or 1.05 end
  return mult
end

--- Lap-clock formatting: m:ss.mmm
function Practice.FormatMs(ms)
  ms = math.max(0, math.floor(ms or 0))
  local m = math.floor(ms / 60000)
  local s = math.floor((ms % 60000) / 1000)
  local r = ms % 1000
  return ('%d:%02d.%03d'):format(m, s, r)
end

--- Driving numbers for one AI car, from that car's own handling after its tune (Damon
--- 2026-10-12: street cars wiped out on the race-car profile, race cars were held back).
--- stats: top (m/s, after any top-speed boost), traction (fTractionCurveMax, in g),
--- drive (fInitialDriveForce). use: how hard the AI leans on the car (gripUse, brakeUse,
--- accelScale). tune: per-model multipliers { grip, top, brake, accel }. base: track
--- physics, only its vmin is kept. Returns { vmax, vmin, aLat, aBrake, aAccel }.
function Practice.CarPhysics(stats, use, tune, base)
  use, tune, base = use or {}, tune or {}, base or {}
  local g = 9.81
  local top = (stats.top or 0) > 0 and stats.top or (base.vmax or 60.0)
  local traction = (stats.traction or 0) > 0 and stats.traction or 2.0
  local drive = (stats.drive or 0) > 0 and stats.drive or 0.3
  local aLat = traction * g * (use.gripUse or 1.0) * (tune.grip or 1.0)
  local aAccel = drive * g * (use.accelScale or 3.0) * (tune.accel or 1.0)
  if aAccel < 5.0 then aAccel = 5.0 elseif aAccel > 32.0 then aAccel = 32.0 end
  return {
    vmax   = top * (tune.top or 1.0),
    vmin   = base.vmin or 12.0,
    aLat   = aLat,
    aBrake = aLat * (use.brakeUse or 1.1) * (tune.brake or 1.0),
    aAccel = aAccel,
  }
end

--- Balance of performance (Damon 2026-10-25: a car that suits one track is too fast or too
--- slow on another). Cars are balanced per class per track instead of one by one: every car
--- in a class is set to that class's target on that track, so a GT3 grid drives alike.

--- The class (set label) a model races in at a track: the first set that lists it.
function Practice.ClassOf(sets, model)
  if type(sets) ~= 'table' or not model then return nil end
  local m = string.lower(model)
  for _, set in ipairs(sets) do
    for _, name in ipairs(set.models or {}) do
      if string.lower(name) == m then return set.label end
    end
  end
  return nil
end

--- A class's target on a track: the shared class target with the track's own values on top.
--- Returns { top (m/s), grip (fTractionCurveMax), power (fInitialDriveForce) } or nil.
function Practice.BalanceTarget(classes, trackClasses, label)
  if not label then return nil end
  local base = classes and classes[label]
  local over = trackClasses and trackClasses[label]
  if not base and not over then return nil end
  local out = {}
  for k, v in pairs(base or {}) do out[k] = v end
  for k, v in pairs(over or {}) do out[k] = v end
  return out
end

--- What to do to one car to hit its class target. stats: top (estimated m/s before any
--- boost), traction, drive. Returns grip and power to write, the top-speed ceiling, and the
--- power boost (percent, 0..maxBoost) that lifts a slower car toward the ceiling.
function Practice.Balance(target, stats, maxBoost)
  target, stats = target or {}, stats or {}
  local out = {
    grip  = target.grip or stats.traction,
    power = target.power or stats.drive,
    top   = target.top,
    boost = 0,
  }
  if target.top and (stats.top or 0) > 0 and stats.top < target.top then
    out.boost = math.min(maxBoost or 60, (target.top / stats.top - 1) * 100)
  end
  return out
end
