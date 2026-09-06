dofile('shared/lines.lua')
local cfg = { recordSpacing = 12.0, minPoints = 10, maxPoints = 50, closeRadius = 40.0 }
-- closed: n points around a circle (ends next to its start); open: a straight line
local function lap(n, close)
  local pts = {}
  for i = 1, n do
    if close then
      local a = (i - 1) / n * 2 * math.pi
      pts[i] = { x = 100.0 * math.cos(a), y = 100.0 * math.sin(a), z = 30.0, h = 0.0 }
    else
      pts[i] = { x = i * 10.0, y = 0.0, z = 30.0, h = 90.0 }
    end
  end
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
TEST('Lines.Smooth flattens a zigzag, keeps count, wraps on closed loops, recomputes heading', function()
  local pts = {}
  for i = 1, 20 do pts[i] = { x = i * 10.0, y = (i % 2 == 0) and 2.0 or -2.0, z = 30.0, h = 0.0 } end
  local out = Lines.Smooth(pts, 2, 2, false)
  EQ(#out, 20)
  TRUTHY(math.abs(out[10].y) < 1.0, 'wobble reduced')
  EQ(out[1].x, 10.0); EQ(out[20].x, 200.0)          -- open line keeps its ends
  TRUTHY(out[10].h > 260 and out[10].h < 280, 'heading east ~270: ' .. tostring(out[10].h))
  local circle = {}
  for i = 1, 36 do local a = (i - 1) / 36 * 2 * math.pi; circle[i] = { x = 100 * math.cos(a), y = 100 * math.sin(a), z = 0 } end
  local c = Lines.Smooth(circle, 2, 1, true)
  TRUTHY(math.abs(math.sqrt(c[1].x ^ 2 + c[1].y ^ 2) - 100) < 5.0, 'closed wrap keeps the first point near the circle')
end)
