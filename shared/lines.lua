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
