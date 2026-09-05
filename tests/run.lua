-- Minimal test runner: dofile every tests/test_*.lua, count passes/failures.
package.path = './?.lua;./?/init.lua;' .. package.path
local passed, failed = 0, 0
function TEST(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; io.write('  ok   ', name, '\n')
  else failed = failed + 1; io.write('  FAIL ', name, '\n       ', tostring(err), '\n') end
end
function EQ(a, b, msg)
  if a ~= b then error((msg or 'EQ') .. (': expected %s got %s'):format(tostring(b), tostring(a)), 2) end
end
function TRUTHY(v, msg) if not v then error((msg or 'expected truthy'), 2) end end
function FALSY(v, msg) if v then error((msg or 'expected falsy'), 2) end end

dofile('tests/stubs.lua')
local p = io.popen('ls tests/test_*.lua')
for file in p:lines() do io.write(file, '\n'); dofile(file) end
p:close()
io.write(('\n%d passed, %d failed\n'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
