dofile('shared/lines.lua')
local cfg = { recordSpacing = 12.0, minPoints = 10, maxPoints = 50, closeRadius = 40.0 }
local function lap(n, close)
  local pts = {}
  for i = 1, n do pts[i] = { x = i * 10.0, y = 0.0, z = 30.0, h = 90.0 } end
  if close then pts[n] = { x = 5.0, y = 5.0, z = 30.0 } end
  return pts
end
TEST('Lines.Validate accepts a lap and reports closure', function()
  local ok, err, info = Lines.Validate('main', lap(20, true), cfg)
  TRUTHY(ok, err); EQ(info.count, 20); TRUTHY(info.closed, 'closed')
  local ok2, _, info2 = Lines.Validate('main', lap(20, false), cfg)
  TRUTHY(ok2); FALSY(info2.closed, 'open line')
end)
TEST('Lines.Validate rejects bad names, short, long, gappy and malformed lines', function()
  local _, e = Lines.Validate('Bad Name', lap(20), cfg); EQ(e, 'bad_name')
  _, e = Lines.Validate('main', lap(5), cfg); EQ(e, 'too_short')
  _, e = Lines.Validate('main', lap(60), cfg); EQ(e, 'too_long')
  local g = lap(20); g[10].x = 900.0
  _, e = Lines.Validate('main', g, cfg); EQ(e, 'gap')
  local m = lap(20); m[3] = { x = 'a', y = 1, z = 1 }
  _, e = Lines.Validate('main', m, cfg); EQ(e, 'bad_point')
  _, e = Lines.Validate('main', 'nope', cfg); EQ(e, 'bad_points')
end)
