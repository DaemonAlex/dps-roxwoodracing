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
