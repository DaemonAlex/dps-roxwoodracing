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
TEST('Practice.Relative and Decide: slow behind a car ahead and aim past its free side', function()
  local aware = { range = 40.0, lateral = 5.0, minSpeed = 12.0, overtakeOffset = 3.5, passWithin = 25.0 }
  local ahead, lateral = Practice.Relative({x=0,y=0}, {x=0,y=1}, {x=2,y=20})
  EQ(ahead, 20.0); EQ(lateral, 2.0)   -- +x while facing +y is the right-hand side
  local speed, off = Practice.Decide(30.0, { { ahead = 20.0, lateral = 2.0 } }, aware)
  EQ(speed, 15.0); EQ(off, -3.5)      -- car ahead sits right, pass on the left
  speed, off = Practice.Decide(30.0, { { ahead = 20.0, lateral = -2.0 } }, aware)
  EQ(off, 3.5)
  speed, off = Practice.Decide(30.0, { { ahead = -5.0, lateral = 0.0 }, { ahead = 60.0, lateral = 0.0 } }, aware)
  EQ(speed, 30.0); EQ(off, 0.0)
  speed = Practice.Decide(30.0, { { ahead = 2.0, lateral = 0.0 } }, aware)
  EQ(speed, 12.0)
end)
TEST('Practice.OffsetPoint shifts to the right of travel', function()
  local pts = { {x=0,y=0,z=1}, {x=0,y=10,z=1} }
  local x, y = Practice.OffsetPoint(pts, 1, 2, 3.5)
  EQ(x, 3.5); EQ(y, 0.0)
end)
TEST('Practice.Decide only starts the pass move inside passWithin', function()
  local aware = { range = 50.0, lateral = 6.0, minSpeed = 9.0, overtakeOffset = 3.5, passWithin = 25.0 }
  local speed, off = Practice.Decide(60.0, { { ahead = 40.0, lateral = 1.0 } }, aware)
  EQ(off, 0.0); EQ(speed, 48.0)
  speed, off = Practice.Decide(60.0, { { ahead = 20.0, lateral = 1.0 } }, aware)
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
