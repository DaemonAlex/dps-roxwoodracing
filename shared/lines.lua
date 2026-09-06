-- Validation for recorded practice lines. Pure; shared by server and tests.
Lines = Lines or {}

--- Returns ok, err, info. Points are { x, y, z, h } tables.
function Lines.Validate(name, points, cfg)
  cfg = cfg or {}
  if type(name) ~= 'string' or not name:match('^[a-z0-9_]+$') or #name > 40 then return false, 'bad_name' end
  if type(points) ~= 'table' then return false, 'bad_points' end
  local n = #points
  if n < (cfg.minPoints or 10) then return false, 'too_short' end
  if n > (cfg.maxPoints or 2000) then return false, 'too_long' end
  local maxGap = (cfg.recordSpacing or 12.0) * 6
  for i = 1, n do
    local p = points[i]
    if type(p) ~= 'table' or type(p.x) ~= 'number' or type(p.y) ~= 'number' or type(p.z) ~= 'number' then
      return false, 'bad_point'
    end
    if p.h ~= nil and type(p.h) ~= 'number' then return false, 'bad_point' end
    if i > 1 then
      local q = points[i - 1]
      local d = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
      if d > maxGap then return false, 'gap' end
    end
  end
  local a, b = points[1], points[n]
  local closing = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
  return true, nil, { count = n, closed = closing <= (cfg.closeRadius or 40.0) }
end

--- Smooth a line: each point becomes the average of itself and `radius` neighbours on
--- either side, repeated `passes` times. Closed loops wrap; open lines keep their ends.
--- Heading is recomputed from the smoothed neighbours. Returns a new table.
function Lines.Smooth(pts, radius, passes, closed)
  local n = #pts
  if n < 3 then return pts end
  radius, passes = radius or 2, passes or 2
  local cur = pts
  for _ = 1, passes do
    local out = {}
    for i = 1, n do
      local sx, sy, sz, cnt = 0.0, 0.0, 0.0, 0
      for k = -radius, radius do
        local j = i + k
        if closed then j = ((j - 1) % n) + 1 end
        if j >= 1 and j <= n then
          local q = cur[j]
          sx, sy, sz, cnt = sx + q.x, sy + q.y, sz + q.z, cnt + 1
        end
      end
      if not closed and (i == 1 or i == n) then
        out[i] = { x = cur[i].x, y = cur[i].y, z = cur[i].z }
      else
        out[i] = { x = sx / cnt, y = sy / cnt, z = sz / cnt }
      end
    end
    cur = out
  end
  for i = 1, n do
    local nxt = cur[i + 1] or (closed and cur[1]) or cur[i]
    local prv = cur[i - 1] or (closed and cur[n]) or cur[i]
    local dx, dy = nxt.x - prv.x, nxt.y - prv.y
    -- GTA heading: 0 = north (+y), increases counter-clockwise
    cur[i].h = (math.deg(math.atan(-dx, dy)) + 360.0) % 360.0
  end
  return cur
end

--- A variant of a line: a smooth lateral drift (sum of three slow sine waves, random
--- phase from `seed`) of at most `amplitude` metres either side, then smoothed. Same
--- point count as the source so indices still line up. Deterministic per seed.
function Lines.Vary(pts, seed, amplitude, closed)
  local n = #pts
  if n < 3 then return pts end
  local state = (seed or 1) % 2147483647
  local function rand()
    state = (state * 48271) % 2147483647
    return state / 2147483647
  end
  local terms, total = {}, 0.0
  for k = 1, 3 do
    local amp = (0.4 + 0.6 * rand()) / k
    terms[k] = { freq = k + math.floor(rand() * 2), phase = rand() * 2 * math.pi, amp = amp }
    total = total + amp
  end
  for _, t in ipairs(terms) do t.amp = t.amp / total * amplitude end   -- worst case = amplitude
  local out = {}
  for i = 1, n do
    local u = (i - 1) / n * 2 * math.pi
    local off = 0.0
    for _, t in ipairs(terms) do off = off + t.amp * math.sin(t.freq * u + t.phase) end
    local a = pts[i]
    local b = pts[i + 1] or (closed and pts[1]) or pts[i]
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then out[i] = { x = a.x, y = a.y, z = a.z }
    else out[i] = { x = a.x + (dy / len) * off, y = a.y - (dx / len) * off, z = a.z } end
  end
  return Lines.Smooth(out, 1, 1, closed)
end

--- Per-point target speed (m/s) written to pts[i].v: vmax on straights, down to vmin
--- where the line turns by `fullTurnDeg` or more over the next three points (~36 m),
--- then each point takes the minimum of the next `brakePts` points so braking starts
--- before the corner. Modifies pts in place and returns it.
function Lines.SpeedProfile(pts, closed, vmax, vmin, brakePts, fullTurnDeg)
  local n = #pts
  if n < 4 then for i = 1, n do pts[i].v = vmax end return pts end
  local function wrap(i) if i > n then return closed and (i - n) or n end return i end
  local function dir(i)
    if not closed and i >= n then i = n - 1 end   -- open end: keep the last segment's heading
    local a, b = pts[i], pts[wrap(i + 1)]
    return math.atan(b.y - a.y, b.x - a.x)
  end
  local full = math.rad(fullTurnDeg or 45)
  local raw = {}
  for i = 1, n do
    local a1, a2 = dir(i), dir(wrap(i + 3))
    local d = math.abs(a2 - a1)
    if d > math.pi then d = 2 * math.pi - d end
    local f = math.min(1.0, d / full)
    raw[i] = vmax - (vmax - vmin) * f
  end
  for i = 1, n do
    local v = raw[i]
    for k = 1, (brakePts or 4) do
      local j = i + k
      if j > n then if closed then j = j - n else break end end
      if raw[j] < v then v = raw[j] end
    end
    pts[i].v = v
  end
  return pts
end

--- Physics speed profile written to pts[i].v. Corner radius at each point from the
--- circumcircle of its neighbours; corner speed = sqrt(aLat * r) capped at vmax; then a
--- backward pass limits speed by braking (aBrake) into each bend and a forward pass by
--- acceleration (aAccel) out of it. Closed loops are passed around twice. Returns pts.
function Lines.SpeedProfilePhysics(pts, closed, params)
  local n = #pts
  local vmax, vmin = params.vmax or 90.0, params.vmin or 12.0
  local aLat, aBrake, aAccel = params.aLat or 18.0, params.aBrake or 20.0, params.aAccel or 10.0
  if n < 3 then for i = 1, n do pts[i].v = vmax end return pts end
  local function wrap(i)
    if closed then return ((i - 1) % n) + 1 end
    if i < 1 then return 1 elseif i > n then return n end
    return i
  end
  local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
  -- radius from three points: r = abc / (4 * area)
  for i = 1, n do
    local a, b, c = pts[wrap(i - 1)], pts[i], pts[wrap(i + 1)]
    local ab, bc, ca = dist(a, b), dist(b, c), dist(c, a)
    local area2 = math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
    local v = vmax
    if area2 > 1e-6 then
      local r = (ab * bc * ca) / (2 * area2)
      v = math.min(vmax, math.sqrt(aLat * r))
    end
    pts[i].v = math.max(vmin, v)
  end
  local rounds = closed and 2 or 1
  for _ = 1, rounds do
    for i = n, 1, -1 do                     -- braking: v_i <= sqrt(v_next^2 + 2 a d)
      local j = wrap(i + 1)
      if j ~= i then
        local d = dist(pts[i], pts[j])
        local lim = math.sqrt(pts[j].v ^ 2 + 2 * aBrake * d)
        if pts[i].v > lim then pts[i].v = lim end
      end
    end
    for i = 1, n do                         -- acceleration: v_i <= sqrt(v_prev^2 + 2 a d)
      local j = wrap(i - 1)
      if j ~= i then
        local d = dist(pts[j], pts[i])
        local lim = math.sqrt(pts[j].v ^ 2 + 2 * aAccel * d)
        if pts[i].v > lim then pts[i].v = lim end
      end
    end
  end
  return pts
end

--- For a closed loop: drop the tail points recorded after the car had already come back
--- past the start (the overlap), so the last point sits just before the first.
--- Looks at the last `window` points, keeps up to the one nearest the start, and drops
--- that one too if it practically coincides with the start. Returns a new table.
function Lines.TrimClosure(pts, spacing, window)
  local n = #pts
  window = math.min(window or 40, n - 3)
  if n < 6 then return pts end
  local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
  local best, bestD = n, math.huge
  for i = n - window, n do
    local di = d(pts[i], pts[1])
    if di < bestD then best, bestD = i, di end
  end
  local last = best
  if bestD < (spacing or 12.0) * 0.5 then last = best - 1 end
  local out = {}
  for i = 1, last do out[i] = pts[i] end
  return out
end
