dofile('shared/practice.lua')
TEST('Practice.StartIndex spreads cars evenly and NextIndex wraps', function()
  EQ(Practice.StartIndex(1, 348, 4), 1); EQ(Practice.StartIndex(2, 348, 4), 88)
  EQ(Practice.StartIndex(4, 348, 4), 262)
  local j, w = Practice.NextIndex(346, 348, 3); EQ(j, 1); TRUTHY(w, 'wrapped')
  j, w = Practice.NextIndex(10, 348, 3); EQ(j, 13); FALSY(w)
end)
TEST('Practice.Extent finds the centre and reach of a line', function()
  local pts = { {x=0,y=0,z=0}, {x=100,y=0,z=0}, {x=100,y=100,z=0}, {x=0,y=100,z=0} }
  local c, r = Practice.Extent(pts)
  EQ(c.x, 50.0); EQ(c.y, 50.0); TRUTHY(math.abs(r - 70.71) < 0.1, 'radius')
end)
TEST('Practice.NearestIndex picks the closest point', function()
  local pts = { {x=0,y=0,z=0}, {x=100,y=0,z=0}, {x=200,y=0,z=0} }
  EQ(Practice.NearestIndex(pts, {x=90,y=5,z=0}), 2)
  EQ(Practice.NearestIndex(pts, {x=-50,y=0,z=0}), 1)
end)
TEST('Practice.PrevIndex walks backwards with wrap', function()
  EQ(Practice.PrevIndex(20, 348, 12), 8)
  EQ(Practice.PrevIndex(5, 348, 12), 341)
end)
TEST('Practice.Relative, BendAhead and Decide: racecraft', function()
  local aware = { range = 40.0, lateral = 5.0, minSpeed = 12.0, overtakeOffset = 3.5, passWithin = 25.0,
    closeGap = 7.0, closeLateral = 2.5, closeFactor = 0.9, slipRange = 25.0, slipLateral = 3.0, slipBonus = 1.06,
    lateBrakeRange = 20.0, lateBrakeFactor = 1.05, defendRange = 18.0, defendOffset = 2.5 }
  local ahead, lateral = Practice.Relative({x=0,y=0}, {x=0,y=1}, {x=2,y=20})
  EQ(ahead, 20.0); EQ(lateral, 2.0)
  -- straight: pass on the free side, slipstream + late braking stack
  local speed, off = Practice.Decide(30.0, { { ahead = 20.0, lateral = 2.0 } }, aware, { bend = 0 })
  EQ(off, -3.5); TRUTHY(math.abs(speed - 30.0 * 1.06 * 1.05) < 0.01, tostring(speed))
  -- right-hander coming: aim for the inside (right) regardless of where the car ahead sits
  speed, off = Practice.Decide(30.0, { { ahead = 20.0, lateral = -2.0 } }, aware, { bend = 1 })
  EQ(off, 3.5)
  -- right on its tail and directly behind: lift to 90%
  speed = Practice.Decide(30.0, { { ahead = 5.0, lateral = 0.5 } }, aware, { bend = 0 })
  EQ(speed, 27.0)
  -- nobody ahead, attacker close behind on a straight: close the door on its side
  speed, off = Practice.Decide(30.0, { { ahead = -10.0, lateral = 1.5 } }, aware, { bend = 0 })
  EQ(speed, 30.0); EQ(off, 2.5)
  -- same attacker but in a corner: no blocking
  speed, off = Practice.Decide(30.0, { { ahead = -10.0, lateral = 1.5 } }, aware, { bend = -1 })
  EQ(off, 0.0)
  -- clear road
  speed, off = Practice.Decide(30.0, { { ahead = 60.0, lateral = 0.0 } }, aware, { bend = 0 })
  EQ(speed, 30.0); EQ(off, 0.0)
  -- BendAhead: falling heading = right turn
  local pts = {}
  for i = 1, 10 do pts[i] = { h = 90.0 - (i - 1) * 4.0 } end
  EQ(Practice.BendAhead(pts, 1, 10, 6, false), 1)
  for i = 1, 10 do pts[i] = { h = 90.0 + (i - 1) * 4.0 } end
  EQ(Practice.BendAhead(pts, 1, 10, 6, false), -1)
  for i = 1, 10 do pts[i] = { h = 350.0 + (i - 1) * 0.5 } end
  EQ(Practice.BendAhead(pts, 1, 10, 6, false), 0)
end)
TEST('Practice.OffsetPoint shifts to the right of travel', function()
  local pts = { {x=0,y=0,z=1}, {x=0,y=10,z=1} }
  local x, y = Practice.OffsetPoint(pts, 1, 2, 3.5)
  EQ(x, 3.5); EQ(y, 0.0)
end)
TEST('Practice.Decide only starts the pass move inside passWithin', function()
  local aware = { range = 50.0, lateral = 6.0, minSpeed = 9.0, overtakeOffset = 3.5, passWithin = 25.0 }
  local speed, off = Practice.Decide(60.0, { { ahead = 40.0, lateral = 1.0 } }, aware, { bend = 0 })
  EQ(off, 0.0); EQ(speed, 60.0)
  speed, off = Practice.Decide(60.0, { { ahead = 20.0, lateral = 1.0 } }, aware, { bend = 0 })
  EQ(off, -3.5)
end)
TEST('Practice.AimPoints scales with speed and clamps; Forward is circular', function()
  EQ(Practice.AimPoints(0.0, 2.0, 12.0, 4, 14), 4)
  EQ(Practice.AimPoints(30.0, 2.0, 12.0, 4, 14), 5)
  EQ(Practice.AimPoints(60.0, 2.0, 12.0, 4, 14), 10)
  EQ(Practice.AimPoints(200.0, 2.0, 12.0, 4, 14), 14)
  EQ(Practice.Forward(340, 5, 348), 13)
  EQ(Practice.Forward(5, 340, 348), 335)
  EQ(Practice.Forward(7, 7, 348), 0)
end)
TEST('Practice.AimByCurvature aims far on a straight and short into a bend', function()
  local pts = {}
  for i = 1, 30 do pts[i] = { x = i, y = 0, z = 0, h = (i <= 20) and 270.0 or (270.0 + (i - 20) * 10.0) } end
  EQ(Practice.AimByCurvature(pts, 1, 30, 2, 14, 15, false), 14)     -- straight: full aim
  EQ(Practice.AimByCurvature(pts, 18, 30, 2, 14, 15, false), 3)     -- 21 is +10, 22 is +20 > 15
  EQ(Practice.AimByCurvature(pts, 24, 30, 2, 14, 15, false), 2)     -- inside the bend: floor
  local ring = {}
  for i = 1, 36 do ring[i] = { x = 0, y = 0, z = 0, h = (i - 1) * 10.0 } end
  EQ(Practice.AimByCurvature(ring, 35, 36, 2, 14, 15, true), 2)     -- wraps and stays short
end)
TEST('Practice.AimByChord aims far on a straight and shortens at the turn-in', function()
  local pts = {}
  for i = 1, 20 do pts[i] = { x = i * 12.0, y = 0.0, z = 0 } end                 -- straight east
  for i = 21, 40 do pts[i] = { x = 240.0 + 12.0, y = (i - 20) * 12.0, z = 0 } end -- then north
  EQ(Practice.AimByChord(pts, { x = 0, y = 0 }, 1, 40, 2, 14, 1.5, false), 14)   -- all straight ahead
  local k = Practice.AimByChord(pts, { x = 168, y = 0 }, 14, 40, 2, 14, 1.5, false)
  EQ(k, 6)                                                                       -- reaches the corner point 20, not past it
  EQ(Practice.DistToSegment({ x = 5, y = 3 }, { x = 0, y = 0 }, { x = 10, y = 0 }), 3.0)
end)
TEST('Practice.ShortName, RollingAvg, PaceMult, FormatMs', function()
  EQ(Practice.ShortName('Damon Stor'), 'DAMON'); EQ(Practice.ShortName('j.r. 77'), 'JR'); EQ(Practice.ShortName(''), 'PLYR')
  local r, avg = Practice.RollingAvg({}, 100000, 5); EQ(#r, 1); EQ(avg, 100000)
  r, avg = Practice.RollingAvg({ 90000, 92000, 94000, 96000, 98000 }, 100000, 5); EQ(#r, 5); EQ(r[1], 92000); EQ(avg, 96000)
  local _, none = Practice.RollingAvg({}, nil, 5); EQ(none, nil)
  -- AI lapped 90 s at full pace; player average 100 s -> aim 97 s -> 0.928
  local m = Practice.PaceMult(90000, 1.0, 100000, 0.03, 0.75, 1.05); TRUTHY(math.abs(m - 0.9278) < 0.001, tostring(m))
  -- AI lapped 100 s while running at 0.9 (=> 90 s at full); player average 80 s -> clamp to 1.05
  EQ(Practice.PaceMult(100000, 0.9, 80000, 0.03, 0.75, 1.05), 1.05)
  EQ(Practice.PaceMult(90000, 1.0, 200000, 0.03, 0.75, 1.05), 0.75)
  EQ(Practice.PaceMult(nil, 1.0, 100000), nil)
  EQ(Practice.FormatMs(83456), '1:23.456')
end)

TEST('Practice.Cluster groups lines into tracks by location', function()
  local function loop(cx, cy, r, n, name)
    local pts = {}
    for i = 1, n do local a = (i - 1) / n * 2 * math.pi; pts[i] = { x = cx + r * math.cos(a), y = cy + r * math.sin(a), z = 0 } end
    return { name = name, pts = pts }
  end
  local lines = { loop(0, 0, 500, 40, 'main'), loop(0, 0, 520, 40, 'main#1'), loop(0, 30, 480, 40, 'wide'), loop(9000, 9000, 400, 40, 'desert') }
  local tracks = Practice.Cluster(lines, 1500.0)
  assert(#tracks == 2, 'two tracks, got ' .. #tracks)
  assert(tracks[1].id == 'desert' and tracks[2].id == 'main', 'ids sorted: ' .. tracks[1].id .. ',' .. tracks[2].id)
  assert(#tracks[2].lines == 3 and tracks[2].lines[1].name == 'main', 'main track keeps 3 lines, base first')
  assert(tracks[2].radius > 500 and tracks[2].radius < 600, 'merged reach ' .. tracks[2].radius)
  assert(math.abs(tracks[1].centre.x - 9000) < 1, 'desert centre')
end)
