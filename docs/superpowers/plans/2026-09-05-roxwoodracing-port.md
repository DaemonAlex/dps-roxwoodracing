# dps-roxwoodracing Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn rox_speedway v2.4.2 into `dps-roxwoodracing`: a [dps]-shaped FiveM resource with a `roxwoodracing` job, society money through Renewed-Banking, autosensed vendor integrations, Spec and Open lobby modes with tune presets, and zero scan loops.

**Architecture:** Port, don't rewrite. Existing lobby/race/ranking/ghost/pit code moves file-by-file into `bridge/`, `integrations/`, `config/`, `client/`, `server/`. Every vendor call goes through one integration file with a detect-at-boot + fallback. Pure logic (validation, ranking sort, payout maths, plate generation, stats merge) is extracted into `shared/` modules that run under plain Lua 5.4 so they can be unit-tested off-server.

**Tech Stack:** FiveM (cerulean, lua54), ox_lib 3.39 (`lib.zones`, `lib.points`, `lib.callback`, `lib.inputDialog`, `lib.registerContext`, `lib.notify`), oxmysql, qbx_core (native exports, no GetCoreObject), Renewed-Banking, qbx_management, wasabi_carlock, ox_fuel, ox_target, jg-advancedgarages. Tests: Lua 5.4 on the fivem VM (`/usr/bin/lua5.4`), a tiny in-repo runner.

**Spec:** `docs/superpowers/specs/2026-09-05-roxwoodracing-design.md`

## Global Constraints

- Resource name is exactly `dps-roxwoodracing`; event/callback prefix is exactly `dps-roxwoodracing:`; no `speedway:` or `rox_speedway:` string may remain in Lua/HTML/JS.
- Job name is exactly `roxwoodracing`; society account name = job name.
- No `while true do Wait(0)` and no periodic entity scans. Per-frame threads may exist only while a bounded activity is happening (countdown, ghost collision loop during a race, pit sequence) and must end with it.
- Vendor names appear only inside `integrations/*.lua` and `bridge/*.lua`.
- Payouts: podium 5000/3000/1500, best lap 1000, show-up 500; pool split 60/30/10; default `Economy.purseSource = 'society'`.
- Tune presets: Stock = no mods; Street = engine 2, brakes 2, gearbox 2; Race = max engine/brakes/gearbox + turbo.
- Stats table is `dps_roxwoodracing_stats`; first boot renames `speedway_stats` if present.
- Track keys `Short_Track`, `Drift_Track`, `Speed_Track`, `Long_Track` are unchanged.
- Brand accent in NUI is `#ff7a45`.
- Git: work on branch `port-to-dps`, plain commit messages, **no attribution footers**, never push to `main`.
- Standing DPS rules that apply to the deploy tasks: read install docs before touching a vendor; one config edit at a time with a report; move old resource to backups, never delete; full server reboot, never `ensure`.

---

## File Structure (final)

```
dps-roxwoodracing/
  fxmanifest.lua
  shared/
    locale.lua          Locale(key, ...) from locales/en.lua           [new]
    validate.lua        Validate.CreateArgs(args, cfg), Validate.Plate  [new, pure]
    ranking.lua         Ranking.SortBoard(board, cp), Ranking.BuildResults [extracted, pure]
    payouts.lua         Payouts.Compute(results, bestLapPid, cfg, pool, balance) [new, pure]
    plates.lua          Plates.FromName(first, last, fallback, used)   [extracted, pure]
    tune.lua            Tune.Presets, Tune.ModsFor(preset)             [new, pure]
  bridge/
    init.lua            Bridge.Framework detection (shared)            [rewritten]
    server.lua          Bridge.GetPlayer*/Money/Job                    [ported sv_bridge]
    client.lua          Bridge.GetJob(), Bridge.HasJob(name, grade)    [new]
  integrations/
    notify.lua          Notify(title, desc, type, ms)  (client)        [ported]
    target.lua          Target.AddPed(ped, options)    (client)        [extracted]
    keys.lua            Keys.Give(veh, plate)          (client)        [ported c_keys]
    fuel.lua            Fuel.SetFull/Fuel.Set          (client)        [ported c_fuel]
    banking.lua         Banking.*                      (server)        [new]
    garages.lua         Garages.GiveVehicle            (server)        [ported InsertVehicle]
    bossmenu.lua        BossMenu.Register (server) / BossMenu.AddItem (client) [new]
  config/
    config.lua tracks.lua vehicles.lua economy.lua pit.lua
  client/
    main.lua hud.lua ghost.lua pit.lua customs.lua leaderboard.lua
  server/
    lobbies.lua race.lua rewards.lua stats.lua staff.lua leaderboard.lua
  html/
    index.html  (was client/nui/timeout.html)  led.html (was leaderboard/speedway.html)
    LCDMB___.TTF  ads/*.png
  stream/  locales/en.lua  tests/  docs/
```

All modules are plain globals (FiveM resources share one Lua state per side). Shared modules must not touch natives at load time so `lua5.4` can `dofile` them.

---

### Task 0: Working copy, test runner, syntax gate

**Files:**
- Create: `tests/run.lua`, `tests/stubs.lua`, `tests/test_smoke.lua`, `tools/check.sh`
- Modify: `.gitignore` (create)

**Interfaces:**
- Produces: `tools/check.sh` (syntax-checks every `.lua` with `luac5.4 -p`, then runs `tests/run.lua`); `tests/stubs.lua` (fake `GetResourceState`, `exports`, `MySQL`, `TriggerClientEvent`, `GetGameTimer`, `print` capture) used by every later test.

The repo clone lives at `~/scratch/dps-roxwoodracing` on the fivem VM (`ssh debian@10.10.10.10`). All check/test commands run there. Local edits sync with:

```bash
rsync -a --delete --exclude .git /tmp/claude-0/-root--claude/a3d464a8-3f74-4f09-9821-2824549c42de/scratchpad/rox_speedway/ debian@10.10.10.10:~/scratch/dps-roxwoodracing/
```

- [ ] **Step 1: Write the runner**

`tests/run.lua`:
```lua
-- Minimal test runner: dofile every tests/test_*.lua, count passes/failures.
package.path = './?.lua;./?/init.lua;' .. package.path
local passed, failed = 0, 0
local current = ''
function TEST(name, fn)
  current = name
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
```

`tests/stubs.lua`:
```lua
-- Stubs for FiveM globals so shared/ and pure server modules load under lua5.4.
STUB = { started = {}, clientEvents = {}, queries = {}, prints = {} }
function GetResourceState(name) return STUB.started[name] and 'started' or 'missing' end
function GetCurrentResourceName() return 'dps-roxwoodracing' end
function GetInvokingResource() return 'dps-roxwoodracing' end
function GetGameTimer() return STUB.now or 0 end
function GetPlayerName(pid) return 'Rockstar' .. tostring(pid) end
function TriggerClientEvent(name, target, ...) STUB.clientEvents[#STUB.clientEvents+1] = { name = name, target = target, args = { ... } } end
function TriggerEvent() end
function CreateThread(fn) fn() end
function Wait() end
function joaat(s) return 0 end
-- exports: exports['res']:Fn(...) and exports.res:Fn(...)
exports = setmetatable({}, { __index = function(t, k) return STUB.exports and STUB.exports[k] end })
-- lib.callback.register / lib.print no-ops
lib = { callback = { register = function() end }, print = { warn = function() end, info = function() end } }
-- oxmysql stub records queries and returns canned rows
MySQL = {
  query  = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.rows or {} end },
  single = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.row end },
  insert = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return 1 end },
  scalar = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.scalar end },
}
json = { encode = function(t) local parts = {} for k, v in pairs(t) do parts[#parts+1] = ('"%s":%s'):format(k, tostring(v)) end return '{' .. table.concat(parts, ',') .. '}' end,
         decode = function(s) local t = {} for k, v in s:gmatch('"([^"]+)":([%d%.]+)') do t[k] = tonumber(v) end return t end }
function vector3(x, y, z) return { x = x, y = y, z = z } end
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
function RESET_STUB() STUB.started = {}; STUB.clientEvents = {}; STUB.queries = {}; STUB.rows = nil; STUB.row = nil; STUB.exports = {}; STUB.now = 0 end
RESET_STUB()
```

`tests/test_smoke.lua`:
```lua
TEST('runner works', function() EQ(1 + 1, 2) end)
```

`tools/check.sh`:
```bash
#!/usr/bin/env bash
# Syntax-check every Lua file, then run unit tests. Run from repo root on the fivem VM.
set -e
fail=0
while IFS= read -r f; do
  if ! luac5.4 -p "$f" 2>/tmp/luac.err; then echo "SYNTAX $f: $(cat /tmp/luac.err)"; fail=1; fi
done < <(find . -name '*.lua' -not -path './.git/*')
[ $fail -eq 0 ] || exit 1
echo "syntax ok"
lua5.4 tests/run.lua
```

`.gitignore`:
```
*.bak
```

- [ ] **Step 2: Sync and run**

Run (local): the rsync line above. Then:
```bash
ssh debian@10.10.10.10 'cd ~/scratch/dps-roxwoodracing && chmod +x tools/check.sh && ./tools/check.sh'
```
Expected: `syntax ok`, then `1 passed, 0 failed`.

- [ ] **Step 3: Commit**

```bash
git add tests tools .gitignore
git commit -m "Add lua5.4 test runner, stubs and syntax gate"
```

---

### Task 1: Skeleton rename and file moves (no logic change)

**Files:**
- Modify: `fxmanifest.lua`
- Move: `client/nui/timeout.html → html/index.html`, `client/nui/lobby.html → html/lobby.html`, `client/nui/lobby.js → html/lobby.js`, `leaderboard/speedway.html → html/led.html`, `leaderboard/LCDMB___.TTF → html/LCDMB___.TTF`, `leaderboard/ads → html/ads`, `leaderboard/cl_leaderboard.lua → client/leaderboard.lua`, `leaderboard/sv_leaderboard.lua → server/leaderboard.lua`, `client/c_main.lua → client/main.lua`, `client/c_pit.lua → client/pit.lua`, `client/c_customs.lua → client/customs.lua`, `client/c_function.lua → client/util.lua`, `client/c_keys.lua → integrations/keys.lua`, `client/c_fuel.lua → integrations/fuel.lua`, `server/s_main.lua → server/race.lua`, `server/sv_bridge.lua → bridge/server.lua`
- Delete: `locales/de.lua locales/es.lua locales/fr.lua locales/ru.lua`, `NOTES.md`

**Interfaces:**
- Produces: the new tree; every event string prefixed `dps-roxwoodracing:`.

- [ ] **Step 1: git mv everything**

```bash
cd /tmp/claude-0/-root--claude/a3d464a8-3f74-4f09-9821-2824549c42de/scratchpad/rox_speedway
mkdir -p html bridge integrations shared
git mv client/nui/timeout.html html/index.html
git mv client/nui/lobby.html html/lobby.html
git mv client/nui/lobby.js html/lobby.js
git mv leaderboard/speedway.html html/led.html
git mv leaderboard/LCDMB___.TTF html/LCDMB___.TTF
git mv leaderboard/ads html/ads
git mv leaderboard/cl_leaderboard.lua client/leaderboard.lua
git mv leaderboard/sv_leaderboard.lua server/leaderboard.lua
git mv client/c_main.lua client/main.lua
git mv client/c_pit.lua client/pit.lua
git mv client/c_customs.lua client/customs.lua
git mv client/c_function.lua client/util.lua
git mv client/c_keys.lua integrations/keys.lua
git mv client/c_fuel.lua integrations/fuel.lua
git mv server/s_main.lua server/race.lua
git mv server/sv_bridge.lua bridge/server.lua
git rm -q locales/de.lua locales/es.lua locales/fr.lua locales/ru.lua NOTES.md
rmdir client/nui leaderboard 2>/dev/null || true
```

- [ ] **Step 2: Rename every event/prefix string**

```bash
grep -rl --include='*.lua' --include='*.html' --include='*.js' -e 'speedway:' -e 'rox_speedway' . | grep -v '^./.git/' | xargs sed -i \
  -e 's/rox_speedway:/dps-roxwoodracing:/g' \
  -e 's/speedway:/dps-roxwoodracing:/g' \
  -e "s/exports\['rox_speedway'\]/exports['dps-roxwoodracing']/g" \
  -e 's#nui://rox_speedway/leaderboard/speedway.html#nui://dps-roxwoodracing/html/led.html#g' \
  -e "s/|| 'rox_speedway'/|| 'dps-roxwoodracing'/g" \
  -e 's/\[ROX-Speedway\]/[dps-roxwoodracing]/g' \
  -e 's/\[Speedway\]/[dps-roxwoodracing]/g'
grep -rn -e 'speedway:' -e 'rox_speedway' --include='*.lua' --include='*.html' --include='*.js' . | grep -v '^./.git/' ; echo "exit=$? (1 means clean)"
```
Expected: the final grep prints nothing (`exit=1`). Note: `amir-leaderboard:*` local event names stay; they are internal.

- [ ] **Step 3: Rewrite fxmanifest.lua**

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-roxwoodracing'
author 'DPS Development (base: max_rox_speedway by MaxSuperTech, rox_speedway by DrCannabis/DaemonAlex)'
description 'Roxwood Raceway: lobbies, Spec and Open races, pit crews, LED leaderboard, society-funded purses'
version '3.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config/*.lua',
  'locales/en.lua',
  'shared/*.lua',
  'bridge/init.lua',
}

client_scripts {
  'bridge/client.lua',
  'integrations/notify.lua',
  'integrations/target.lua',
  'integrations/keys.lua',
  'integrations/fuel.lua',
  'integrations/bossmenu.lua',
  'client/util.lua',
  'client/customs.lua',
  'client/hud.lua',
  'client/ghost.lua',
  'client/main.lua',
  'client/pit.lua',
  'client/leaderboard.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'bridge/server.lua',
  'integrations/banking.lua',
  'integrations/garages.lua',
  'integrations/bossmenu.lua',
  'server/stats.lua',
  'server/rewards.lua',
  'server/lobbies.lua',
  'server/race.lua',
  'server/staff.lua',
  'server/leaderboard.lua',
}

ui_page 'html/index.html'

files {
  'locales/en.lua',
  'html/index.html',
  'html/led.html',
  'html/LCDMB___.TTF',
  'html/ads/*.png',
}

file 'stream/def_amir_speedway.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/def_amir_speedway.ytyp'
this_is_a_map 'yes'

dependencies { 'ox_lib', 'oxmysql' }
```
Files named here that do not exist yet (`bridge/init.lua`, `bridge/client.lua`, `integrations/notify.lua`, `integrations/target.lua`, `integrations/bossmenu.lua`, `integrations/banking.lua`, `integrations/garages.lua`, `client/hud.lua`, `client/ghost.lua`, `server/stats.lua`, `server/rewards.lua`, `server/lobbies.lua`, `server/staff.lua`, `shared/*.lua`) are created in Tasks 2–13. Until then the manifest is ahead of the tree; that is fine because nothing boots from this clone.

- [ ] **Step 4: Fix the two `require` lines that break under the new layout**

`client/main.lua` line 3 and `server/race.lua` line 3 and `client/pit.lua` line 5 and `bridge/server.lua` line 7 and `server/leaderboard.lua` line 5 all say `require("config.config")`. Replace each with nothing (the global `Config` is populated by `shared_scripts`):
```bash
sed -i -e 's/^local Config = require("config.config")$/-- Config is a shared global/' \
       -e 's/^local Config = Config or require("config.config")$/-- Config is a shared global/' \
       client/main.lua server/race.lua client/pit.lua bridge/server.lua server/leaderboard.lua
grep -rn 'require("config' . --include='*.lua' | grep -v '^./.git/'; echo "exit=$?"
```
Expected: `exit=1`.

- [ ] **Step 5: Sync, syntax gate, commit**

Run the rsync, then `ssh debian@10.10.10.10 'cd ~/scratch/dps-roxwoodracing && ./tools/check.sh'`.
Expected: `syntax ok`, `1 passed, 0 failed`.

```bash
git add -A
git commit -m "Rename to dps-roxwoodracing and move files into the [dps] layout"
```

---

### Task 2: Split config by topic and add the shared locale helper

**Files:**
- Create: `config/tracks.lua`, `config/vehicles.lua`, `config/economy.lua`, `config/pit.lua`, `shared/locale.lua`
- Modify: `config/config.lua` (shrinks to general settings), `locales/en.lua` (add new keys)
- Test: `tests/test_config.lua`

**Interfaces:**
- Produces: global `Config` with the same keys as before **plus** `Config.Economy`, `Config.Tune`, `Config.OpenClasses`, `Config.Job`; global `Locale(key, ...)`.
- `locales/en.lua` returns a table (unchanged shape); `Locale` reads it through `Config.LocaleTable`.

- [ ] **Step 1: Write the test**

`tests/test_config.lua`:
```lua
TEST('config files load and expose the split tables', function()
  Config = {}
  dofile('config/config.lua'); dofile('config/tracks.lua'); dofile('config/vehicles.lua')
  dofile('config/economy.lua'); dofile('config/pit.lua')
  TRUTHY(Config.Checkpoints.Short_Track, 'tracks')
  EQ(#Config.Checkpoints.Long_Track, 5)
  TRUTHY(Config.PitCrewZones[1].coords, 'pit')
  EQ(Config.Economy.purseSource, 'society')
  EQ(Config.Economy.payouts[1], 5000)
  EQ(Config.Economy.poolSplit[1], 60)
  EQ(Config.Job.name, 'roxwoodracing')
  EQ(Config.Job.grades.director, 2)
  EQ(Config.Tune.Street.mods[11], 2)
  TRUTHY(Config.OpenClasses.Any, 'open classes')
  TRUTHY(#Config.SpecPresets.Super.vehicles > 0, 'presets')
end)

TEST('Locale substitutes numbered args and falls back to key', function()
  Config = { LocaleTable = { hello = 'Hi {1}, {2}' } }
  dofile('shared/locale.lua')
  EQ(Locale('hello', 'A', 'B'), 'Hi A, B')
  EQ(Locale('missing_key'), 'missing_key')
end)
```

- [ ] **Step 2: Run to see it fail**

`./tools/check.sh` on the VM. Expected: FAIL (files missing).

- [ ] **Step 3: Split the config**

Move blocks out of `config/config.lua` **verbatim** (cut and paste, no edits) into:

- `config/tracks.lua`: `Config.SegmentHints`, `Config.StartLinePoints`, `Config.Checkpoints`, `Config.TrackProps`, `Config.GridSpawnPoints`, `Config.FinishLine`, `Config.outCoords`, `Config.LobbyPed`. Start the file with `Config = Config or {}`.
- `config/pit.lua`: `Config.PitCrewZones`, `Config.PitCrewModel`, `Config.PitCrewIdleOffsets`, `Config.PitCrewCrewOffsets`, `Config.PitStopTiming`, `Config.PitCrewIdleAnims`. Start with `Config = Config or {}`.
- `config/vehicles.lua`: `Config.RaceVehicles` renamed to `Config.SpecFallbackVehicles` (used only when the vehicle registry is unavailable), `Config.RaceClasses` renamed to `Config.SpecPresets`, plus the new blocks below.
- `config/economy.lua`: `Config.Rewards`, `Config.EntryFee`, `Config.Stats` moved, plus the new `Config.Economy` and `Config.Job` blocks below. `Config.Rewards`/`Config.EntryFee` stay only so the untouched code keeps loading in this task; Task 6 deletes them.

Append to `config/vehicles.lua`:
```lua
-- Open lobbies: host picks one of these; joiners must be in a vehicle of that class.
-- Numbers are GetVehicleClass() ids.
Config.OpenClasses = {
  Any      = { label = 'Any vehicle',   classes = nil },
  Super    = { label = 'Super',         classes = { [7] = true } },
  Sports   = { label = 'Sports',        classes = { [6] = true, [5] = true } },
  Muscle   = { label = 'Muscle',        classes = { [4] = true } },
  Offroad  = { label = 'Off-road',      classes = { [9] = true } },
  Bikes    = { label = 'Motorcycles',   classes = { [8] = true } },
}

-- Spec lobbies: the lobby-wide tune applied to every spawned car.
-- mods = { [modType] = index }, -1 = stock, 'max' = highest available; toggles = { [modType] = bool }
Config.Tune = {
  Stock  = { label = 'Stock',  mods = {}, toggles = {} },
  Street = { label = 'Street', mods = { [11] = 2, [12] = 2, [13] = 2 }, toggles = {} },
  Race   = { label = 'Race',   mods = { [11] = 'max', [12] = 'max', [13] = 'max' }, toggles = { [18] = true } },
}
Config.TuneOrder = { 'Stock', 'Street', 'Race' }

-- Spec menu grouping: game class id -> label. Any registered vehicle whose class is
-- not listed falls under 'Other'.
Config.SpecClassLabels = {
  [0] = 'Compacts', [1] = 'Sedans', [2] = 'SUVs', [3] = 'Coupes', [4] = 'Muscle',
  [5] = 'Sports Classics', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycles',
  [9] = 'Off-road', [12] = 'Vans', [22] = 'Open Wheel',
}
```

Append to `config/economy.lua`:
```lua
Config.Job = {
  name   = 'roxwoodracing',
  label  = 'Roxwood Raceway',
  grades = { marshal = 0, pitcrew = 1, director = 2, owner = 3 },
  -- Boss menu zone at the paddock office (next to the lobby ped)
  bossCoords = vector3(-2903.5, 8079.2, 44.5),
}

Config.Economy = {
  purseSource = 'society',          -- 'society' (pay from the job account) | 'house' (mint, but log)
  entryFee    = { enabled = true, amount = 1000 },
  poolSplit   = { [1] = 60, [2] = 30, [3] = 10 },
  payouts     = { [1] = 5000, [2] = 3000, [3] = 1500 },
  participationReward = 500,
  bestLapBonus        = 1000,
  vehiclePrize        = nil,        -- e.g. 'sultan3'; nil = off
  prizeGarage         = 'Roxwood Raceway',
  moneyType           = 'cash',     -- player side of every transaction
}
```

- [ ] **Step 4: Write shared/locale.lua and wire en.lua**

`shared/locale.lua`:
```lua
-- Locale(key, ...) : "{1}" "{2}" substitution; unknown keys return the key itself.
function Locale(key, ...)
  local tbl = Config.LocaleTable or {}
  local str = tbl[key] or key
  local args = { ... }
  return (str:gsub('{(%d+)}', function(n) return tostring(args[tonumber(n)] or '') end))
end
```
At the top of `locales/en.lua` the file currently does `return { ... }`. Change it to assign as well:
```lua
Config = Config or {}
Config.LocaleTable = {
  ... existing keys unchanged ...
}
return Config.LocaleTable
```
Add these keys inside the table (alphabetical placement is fine):
```lua
  mode_spec = 'Spec (track cars)',
  mode_open = 'Open (your own car)',
  select_mode = 'Race mode',
  select_open_class = 'Allowed vehicle class',
  select_tune = 'Tune',
  open_need_vehicle = 'Sit in a vehicle you own to join an Open race.',
  open_not_owner = 'That vehicle is not registered to you.',
  open_wrong_class = 'That vehicle is not in the {1} class.',
  purse_short = 'The raceway account could not cover the purse this race. Pool only.',
  staff_only = 'Raceway staff only.',
  raceway_control = 'Raceway Control',
  race_ended_by_staff = 'Race ended by raceway staff.',
```
Then in `client/main.lua` and `server/race.lua` replace the local `loc`/`locale` helpers:
```bash
sed -i -e 's/\bloc(/Locale(/g' client/main.lua
sed -i -e 's/\blocale(/Locale(/g' server/race.lua
```
and delete the now-unused helper definitions (client/main.lua lines 4–11: `local localeTable = require(...)` through `end`; server/race.lua lines 6–13 likewise).

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → expected `syntax ok`, `3 passed, 0 failed`.
```bash
git add -A
git commit -m "Split config by topic, add Locale helper, Economy/Job/Tune/OpenClasses blocks"
```

---

### Task 3: Framework bridge (qbx-first)

**Files:**
- Create: `bridge/init.lua`, `bridge/client.lua`
- Modify: `bridge/server.lua`
- Test: `tests/test_bridge.lua`

**Interfaces:**
- Produces (shared): `Bridge.Framework` ∈ `'qbx' | 'qb' | 'esx' | nil`, `Bridge.Detect()`.
- Produces (server): `Bridge.GetPlayerIdentifier(pid)`, `Bridge.GetPlayerName(pid)`, `Bridge.GetPlayerFirstLast(pid)`, `Bridge.AddMoney(pid, mtype, amount, reason) → bool`, `Bridge.RemoveMoney(pid, mtype, amount, reason) → bool`, `Bridge.GetMoney(pid, mtype) → number`, `Bridge.GetPlayerNameFromDB(identifier)`, `Bridge.GetJob(pid) → {name, grade, isboss} | nil`, `Bridge.HasJob(pid, jobName, minGrade) → bool`.
- Produces (client): `Bridge.GetJob() → {name, grade, isboss}`, `Bridge.HasJob(jobName, minGrade) → bool`.

- [ ] **Step 1: Write the test**

`tests/test_bridge.lua`:
```lua
local function loadBridge()
  Config = { Framework = nil }
  Bridge = nil
  dofile('bridge/init.lua')
  dofile('bridge/server.lua')
end

TEST('detects qbx before qb', function()
  RESET_STUB(); STUB.started = { qbx_core = true, ['qb-core'] = true }
  loadBridge()
  EQ(Bridge.Framework, 'qbx')
end)

TEST('qbx money and job go through exports.qbx_core:GetPlayer', function()
  RESET_STUB(); STUB.started = { qbx_core = true }
  local bal = 5000
  local fakePlayer = {
    PlayerData = { citizenid = 'ABC123', charinfo = { firstname = 'Sam', lastname = 'Rider' },
                   job = { name = 'roxwoodracing', grade = { level = 2 }, isboss = false } },
    Functions = {
      AddMoney = function(_, mtype, amount) bal = bal + amount; return true end,
      RemoveMoney = function(_, mtype, amount) if bal < amount then return false end bal = bal - amount; return true end,
      GetMoney = function(_, mtype) return bal end,
    },
  }
  STUB.exports = { qbx_core = { GetPlayer = function(_, src) return src == 7 and fakePlayer or nil end } }
  loadBridge()
  EQ(Bridge.GetPlayerIdentifier(7), 'ABC123')
  EQ(Bridge.GetPlayerName(7), 'Sam Rider')
  local f, l = Bridge.GetPlayerFirstLast(7); EQ(f, 'Sam'); EQ(l, 'Rider')
  TRUTHY(Bridge.RemoveMoney(7, 'cash', 1000, 'test')); EQ(Bridge.GetMoney(7, 'cash'), 4000)
  FALSY(Bridge.RemoveMoney(7, 'cash', 99999, 'test'))
  TRUTHY(Bridge.AddMoney(7, 'cash', 10, 'test')); EQ(bal, 4010)
  EQ(Bridge.GetJob(7).name, 'roxwoodracing'); EQ(Bridge.GetJob(7).grade, 2)
  TRUTHY(Bridge.HasJob(7, 'roxwoodracing', 2)); FALSY(Bridge.HasJob(7, 'roxwoodracing', 3)); FALSY(Bridge.HasJob(7, 'police', 0))
  FALSY(Bridge.GetPlayerIdentifier(8), 'offline player')
end)

TEST('no framework -> nil framework and safe returns', function()
  RESET_STUB()
  loadBridge()
  EQ(Bridge.Framework, nil)
  EQ(Bridge.GetPlayerIdentifier(1), nil)
  EQ(Bridge.GetMoney(1, 'cash'), 0)
  FALSY(Bridge.HasJob(1, 'roxwoodracing', 0))
end)
```

- [ ] **Step 2: Run to see it fail** — `./tools/check.sh` → FAIL (bridge/init.lua missing).

- [ ] **Step 3: Write bridge/init.lua**

```lua
-- Framework detection, shared by client and server. Order matters: qbx first.
Bridge = Bridge or {}

local function up(name)
  local st = GetResourceState(name)
  return st == 'started' or st == 'starting'
end

function Bridge.Detect()
  if Config.Framework then return Config.Framework end
  if up('qbx_core') then return 'qbx' end
  if up('qb-core') then return 'qb' end
  if up('es_extended') then return 'esx' end
  return nil
end

Bridge.Framework = Bridge.Detect()
print(('[dps-roxwoodracing] framework: %s'):format(Bridge.Framework or 'none'))
```

- [ ] **Step 4: Rewrite bridge/server.lua**

Replace the whole file. Keep the ESX branches from the old file for `GetPlayerIdentifier/GetPlayerName/GetPlayerFirstLast/AddMoney/RemoveMoney/GetMoney/GetAllPlayersWithIdentifier/GetPlayerNameFromDB` verbatim where marked; the qb and qbx branches share one code path because qbx_core's player object keeps `PlayerData` and `Functions`.

```lua
-- Server framework bridge. qbx and qb share the QB player-object shape.
Bridge = Bridge or {}
local fw = Bridge.Framework

local function getPlayer(pid)
  if fw == 'qbx' then return exports.qbx_core:GetPlayer(pid) end
  if fw == 'qb' then return exports['qb-core']:GetCoreObject().Functions.GetPlayer(pid) end
  return nil
end

local function esx()
  return exports['es_extended']:getSharedObject()
end

local function mapMoneyType(mtype)
  if fw == 'esx' and mtype == 'cash' then return 'money' end
  return mtype or 'cash'
end

function Bridge.GetPlayerIdentifier(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    return x and x.getIdentifier() or nil
  end
  return nil
end

function Bridge.GetPlayerName(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local ci = P and P.PlayerData and P.PlayerData.charinfo
    if ci then return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$') end
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    if x and x.getName() then return x.getName() end
  end
  return GetPlayerName(pid) or ('Player ' .. tostring(pid))
end

function Bridge.GetPlayerFirstLast(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local ci = P and P.PlayerData and P.PlayerData.charinfo
    if ci then return ci.firstname, ci.lastname end
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    local name = x and x.getName()
    if name then return name:match('^(%S+)%s*(.*)$') end
  end
  return nil, nil
end

function Bridge.AddMoney(pid, mtype, amount, reason)
  if amount <= 0 then return true end
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid); if not P then return false end
    return P.Functions.AddMoney(mapMoneyType(mtype), amount, reason) ~= false
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return false end
    if mapMoneyType(mtype) == 'bank' then x.addAccountMoney('bank', amount) else x.addMoney(amount) end
    return true
  end
  return false
end

function Bridge.RemoveMoney(pid, mtype, amount, reason)
  if amount <= 0 then return true end
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid); if not P then return false end
    return P.Functions.RemoveMoney(mapMoneyType(mtype), amount, reason) ~= false
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return false end
    local have = mapMoneyType(mtype) == 'bank' and x.getAccount('bank').money or x.getMoney()
    if have < amount then return false end
    if mapMoneyType(mtype) == 'bank' then x.removeAccountMoney('bank', amount) else x.removeMoney(amount) end
    return true
  end
  return false
end

function Bridge.GetMoney(pid, mtype)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    return P and P.Functions.GetMoney(mapMoneyType(mtype)) or 0
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return 0 end
    if mapMoneyType(mtype) == 'bank' then return x.getAccount('bank').money end
    return x.getMoney()
  end
  return 0
end

function Bridge.GetJob(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local j = P and P.PlayerData and P.PlayerData.job
    if not j then return nil end
    local grade = type(j.grade) == 'table' and (j.grade.level or 0) or (tonumber(j.grade) or 0)
    return { name = j.name, grade = grade, isboss = j.isboss == true }
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return nil end
    local j = x.getJob()
    return { name = j.name, grade = j.grade or 0, isboss = (j.grade_name == 'boss') }
  end
  return nil
end

function Bridge.HasJob(pid, jobName, minGrade)
  local j = Bridge.GetJob(pid)
  return j ~= nil and j.name == jobName and j.grade >= (minGrade or 0)
end

-- Character name lookup for offline players (leaderboard idle view).
function Bridge.GetPlayerNameFromDB(identifier)
  if fw == 'qbx' or fw == 'qb' then
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
    if row and row.charinfo then
      local ci = json.decode(row.charinfo)
      if ci then return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$') end
    end
  elseif fw == 'esx' then
    local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
    if row then return ((row.firstname or '') .. ' ' .. (row.lastname or '')):match('^%s*(.-)%s*$') end
  end
  return nil
end
```
Then in `server/race.lua` remove the line `if not Bridge.Framework then return end` guards? No — keep them; they still make sense. `Bridge.InsertVehicle` and `Bridge.GetAllPlayersWithIdentifier` are gone; Task 6 (garages) and Task 13 (leaderboard) replace their callers.

- [ ] **Step 5: Write bridge/client.lua**

```lua
-- Client framework bridge: job lookups only.
Bridge = Bridge or {}
local fw = Bridge.Framework

function Bridge.GetJob()
  if fw == 'qbx' then
    local pd = exports.qbx_core:GetPlayerData()
    local j = pd and pd.job
    if not j then return nil end
    return { name = j.name, grade = (type(j.grade) == 'table' and j.grade.level) or 0, isboss = j.isboss == true }
  elseif fw == 'qb' then
    local pd = exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
    local j = pd and pd.job
    if not j then return nil end
    return { name = j.name, grade = (type(j.grade) == 'table' and j.grade.level) or 0, isboss = j.isboss == true }
  elseif fw == 'esx' then
    local pd = exports['es_extended']:getSharedObject().GetPlayerData()
    local j = pd and pd.job
    if not j then return nil end
    return { name = j.name, grade = j.grade or 0, isboss = (j.grade_name == 'boss') }
  end
  return nil
end

function Bridge.HasJob(jobName, minGrade)
  local j = Bridge.GetJob()
  return j ~= nil and j.name == jobName and j.grade >= (minGrade or 0)
end
```

- [ ] **Step 6: Run tests, commit**

`./tools/check.sh` → `6 passed, 0 failed`.
```bash
git add bridge tests/test_bridge.lua
git commit -m "Bridge: qbx-first detection, job lookups, shared client/server API"
```

---

### Task 4: Client integrations — notify, target, keys, fuel

**Files:**
- Create: `integrations/notify.lua`, `integrations/target.lua`
- Modify: `integrations/keys.lua` (was c_keys), `integrations/fuel.lua` (was c_fuel)
- Modify: `client/main.lua` (call sites), `client/pit.lua` (fuel call sites)
- Test: `tests/test_integrations_client.lua`

**Interfaces:**
- Produces: `Notify(title, desc, ntype, ms)` (replaces `SpeedwayNotify`), `Target.AddPed(ped, options)` where `options` is an ox_target option list `{ {name, label, icon, event, canInteract, distance}, ... }`, `Keys.Give(veh, plate)`, `Fuel.SetFull(veh)`, `Fuel.Set(veh, level)`.
- All four print one `[dps-roxwoodracing] <thing>: <vendor>` line at boot.

- [ ] **Step 1: Write the test**

`tests/test_integrations_client.lua`:
```lua
TEST('Keys picks wasabi_carlock first and calls GiveKey(plate)', function()
  RESET_STUB(); STUB.started = { wasabi_carlock = true, ['qs-vehiclekeys'] = true }
  local got
  STUB.exports = { wasabi_carlock = { GiveKey = function(_, plate) got = plate end } }
  Config = { DebugPrints = false }
  function SetVehicleDoorsLocked() end
  dofile('integrations/keys.lua')
  EQ(Keys.Provider, 'wasabi_carlock')
  Keys.Give(42, 'SAMRIDER')
  EQ(got, 'SAMRIDER')
end)

TEST('Keys falls back to unlock-only when nothing is installed', function()
  RESET_STUB()
  local unlocked
  function SetVehicleDoorsLocked(veh, state) unlocked = { veh, state } end
  dofile('integrations/keys.lua')
  EQ(Keys.Provider, 'none')
  Keys.Give(42, 'X'); EQ(unlocked[2], 1)
end)

TEST('Fuel prefers the ox_fuel statebag', function()
  RESET_STUB(); STUB.started = { ox_fuel = true }
  local set
  Entity = function(veh) return { state = { set = function(_, k, v, r) set = { k, v, r } end } } end
  function SetVehicleFuelLevel() end
  function DoesEntityExist() return true end
  dofile('integrations/fuel.lua')
  EQ(Fuel.Provider, 'ox_fuel')
  Fuel.SetFull(9); EQ(set[1], 'fuel'); EQ(set[2], 100.0); EQ(set[3], true)
end)

TEST('Notify routes to ox_lib when present, prints otherwise', function()
  RESET_STUB(); STUB.started = { ox_lib = true }
  local got
  lib.notify = function(t) got = t end
  dofile('integrations/notify.lua')
  Notify('T', 'D', 'success', 1234)
  EQ(got.title, 'T'); EQ(got.description, 'D'); EQ(got.type, 'success'); EQ(got.duration, 1234)
end)
```

- [ ] **Step 2: Run to see it fail** — `./tools/check.sh` → FAIL (Keys nil / notify missing).

- [ ] **Step 3: Write integrations/notify.lua**

```lua
-- Notifications. Detects once; every caller uses Notify().
local provider = 'print'
if GetResourceState('ox_lib') == 'started' or GetResourceState('ox_lib') == 'starting' then provider = 'ox_lib'
elseif GetResourceState('okokNotify') == 'started' then provider = 'okokNotify' end
print(('[dps-roxwoodracing] notify: %s'):format(provider))

local function mapType(t)
  if t == 'inform' or t == 'info' then return 'inform' end
  if t == 'warning' then return 'warning' end
  if t == 'error' then return 'error' end
  return 'success'
end

function Notify(title, description, ntype, duration)
  if provider == 'ox_lib' then
    lib.notify({ title = title ~= '' and title or nil, description = description, type = mapType(ntype), duration = duration or 5000 })
  elseif provider == 'okokNotify' then
    exports.okokNotify:Alert(title or '', description or '', duration or 5000, mapType(ntype), false)
  else
    print(('[dps-roxwoodracing] %s: %s'):format(tostring(title), tostring(description)))
  end
end

RegisterNetEvent('dps-roxwoodracing:client:notify', function(title, description, ntype, duration)
  Notify(title, description, ntype, duration)
end)
```
Then in `client/main.lua`: delete the old `SpeedwayNotify` function (lines ~465–481 including its `RegisterNetEvent('dps-roxwoodracing:client:notify', ...)`) and `sed -i 's/SpeedwayNotify(/Notify(/g' client/main.lua client/pit.lua`. Delete `SpeedwayAlert` too (unused).

- [ ] **Step 4: Write integrations/target.lua**

```lua
-- Target wrapper: ox_target -> qb-target -> proximity key fallback.
Target = {}
Target.Provider = 'none'
if GetResourceState('ox_target') == 'started' or GetResourceState('ox_target') == 'starting' then Target.Provider = 'ox_target'
elseif GetResourceState('qb-target') == 'started' then Target.Provider = 'qb-target' end
print(('[dps-roxwoodracing] target: %s'):format(Target.Provider))

---@param ped number entity
---@param options table[] ox_target-style: { name, label, icon, event, canInteract, distance }
function Target.AddPed(ped, options)
  if Target.Provider == 'ox_target' then
    exports.ox_target:addLocalEntity(ped, options)
  elseif Target.Provider == 'qb-target' then
    local qb = { options = {}, distance = 2.5 }
    for i, o in ipairs(options) do qb.options[i] = { event = o.event, icon = o.icon, label = o.label, canInteract = o.canInteract } end
    exports['qb-target']:AddTargetEntity(ped, qb)
  else
    -- Fallback: an ox_lib point; the marker thread runs only while the player is near.
    local coords = GetEntityCoords(ped)
    lib.points.new({
      coords = coords, distance = 3.0,
      nearby = function()
        for _, o in ipairs(options) do
          if not o.canInteract or o.canInteract() then
            DrawText3D(coords.x, coords.y, coords.z + 1.0, ('[E] %s'):format(o.label))
            if IsControlJustPressed(0, 38) then TriggerEvent(o.event) end
            break
          end
        end
      end,
    })
  end
end
```
In `client/main.lua` replace the block from `-- Support ox_target, qb-target, or fallback` down to the end of the `else ... end` fallback (old lines 522–583) with:
```lua
    Target.AddPed(ped, {
      { name = 'roxwood_create_lobby', event = 'dps-roxwoodracing:client:createLobby', icon = 'fa-solid fa-flag-checkered', label = Locale('create_lobby'), canInteract = function() return not hasLobby end, distance = 2.5 },
      { name = 'roxwood_join_lobby',   event = 'dps-roxwoodracing:client:joinLobby',   icon = 'fa-solid fa-user-plus',       label = Locale('join_lobby'),   canInteract = function() return hasLobby and not currentLobby end, distance = 2.5 },
    })
```

- [ ] **Step 5: Rewrite integrations/keys.lua**

```lua
-- Vehicle keys. One provider, detected at boot; Keys.Give(veh, plate).
Keys = {}
local order = { 'wasabi_carlock', 'qs-vehiclekeys', 'Renewed-Vehiclekeys', 'qb-vehiclekeys' }
Keys.Provider = 'none'
for _, name in ipairs(order) do
  if GetResourceState(name) == 'started' or GetResourceState(name) == 'starting' then Keys.Provider = name break end
end
print(('[dps-roxwoodracing] keys: %s'):format(Keys.Provider))

function Keys.Give(veh, plate)
  local p = Keys.Provider
  if p == 'wasabi_carlock' then
    pcall(function() exports.wasabi_carlock:GiveKey(plate) end)
  elseif p == 'qs-vehiclekeys' then
    pcall(function() exports['qs-vehiclekeys']:GiveKeys(plate, nil, true) end)
  elseif p == 'Renewed-Vehiclekeys' then
    pcall(function() exports['Renewed-Vehiclekeys']:addKey(plate) end)
  elseif p == 'qb-vehiclekeys' then
    pcall(function() TriggerEvent('vehiclekeys:client:SetOwner', plate) end)
  end
  -- Always unlock as well; key scripts sometimes re-lock on spawn.
  SetVehicleDoorsLocked(veh, 1)
end

RegisterNetEvent('dps-roxwoodracing:client:giveKeys', function(netId, plate)
  local veh = NetworkGetEntityFromNetworkId(netId)
  if veh and veh ~= 0 and DoesEntityExist(veh) then Keys.Give(veh, plate or GetVehicleNumberPlateText(veh)) end
end)
```
Note: `RegisterNetEvent` is not stubbed; add `function RegisterNetEvent() end` and `function NetworkGetEntityFromNetworkId() return 0 end` to `tests/stubs.lua`.
In `client/main.lua` replace `GiveVehicleKeys(veh)` with `Keys.Give(veh, data.plate)`. In `server/race.lua` change `TriggerClientEvent("dps-roxwoodracing:client:giveKeys", pid, netId)` to pass `netId, plate`.

- [ ] **Step 6: Rewrite integrations/fuel.lua**

```lua
-- Fuel. ox_fuel uses the entity statebag; others use their export; natives last.
Fuel = {}
Fuel.Provider = 'native'
local exportsByName = {
  ['LegacyFuel']      = function(veh, lvl) exports['LegacyFuel']:SetFuel(veh, lvl) end,
  ['cdn-fuel']        = function(veh, lvl) exports['cdn-fuel']:SetFuel(veh, lvl) end,
  ['okokGasStation']  = function(veh, lvl) exports['okokGasStation']:SetFuel(veh, lvl) end,
  ['qs-fuelstations'] = function(veh, lvl) exports['qs-fuelstations']:SetFuel(veh, lvl) end,
}
if GetResourceState('ox_fuel') == 'started' or GetResourceState('ox_fuel') == 'starting' then
  Fuel.Provider = 'ox_fuel'
else
  for name in pairs(exportsByName) do
    if GetResourceState(name) == 'started' then Fuel.Provider = name break end
  end
end
print(('[dps-roxwoodracing] fuel: %s'):format(Fuel.Provider))

function Fuel.Set(veh, level)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  level = math.max(0.0, math.min(100.0, level + 0.0))
  if Fuel.Provider == 'ox_fuel' then
    Entity(veh).state:set('fuel', level, true)
  elseif exportsByName[Fuel.Provider] then
    pcall(exportsByName[Fuel.Provider], veh, level)
  end
  pcall(SetVehicleFuelLevel, veh, level)
end

function Fuel.SetFull(veh) Fuel.Set(veh, 100.0) end

RegisterNetEvent('dps-roxwoodracing:client:setFuel', function(netId, level)
  local veh = NetworkGetEntityFromNetworkId(netId)
  Fuel.Set(veh, level)
end)
RegisterNetEvent('dps-roxwoodracing:client:fillFuel', function(netId)
  local veh = NetworkGetEntityFromNetworkId(netId)
  Fuel.SetFull(veh)
end)
```
Then: `sed -i 's/SetFullFuel(/Fuel.SetFull(/g; s/SetFuelLevel(/Fuel.Set(/g' client/main.lua client/pit.lua` and delete the duplicate `dps-roxwoodracing:client:fillFuel` handler in `client/main.lua` (old lines 1178–1181).

- [ ] **Step 7: Run tests, commit**

`./tools/check.sh` → `10 passed, 0 failed`.
```bash
git add integrations client tests
git commit -m "Client integrations: notify, target, keys, fuel with boot-time detection"
```

---

### Task 5: Server integrations — banking and garages

**Files:**
- Create: `integrations/banking.lua`, `integrations/garages.lua`
- Test: `tests/test_banking.lua`

**Interfaces:**
- Produces: `Banking.Provider` ∈ `'Renewed-Banking' | 'qb-banking' | 'none'`; `Banking.EnsureAccount(name, label)`; `Banking.GetBalance(account) → number`; `Banking.Deposit(account, amount, title, message, fromLabel) → bool`; `Banking.Withdraw(account, amount, title, message, toLabel) → bool` (false when the balance is short); `Banking.LogOnly(account, amount, title, message, fromLabel, toLabel)` (house mode ledger line).
- Produces: `Garages.Provider` ∈ `'jg-advancedgarages' | 'none'`; `Garages.GiveVehicle(pid, model, plate) → bool`.

- [ ] **Step 1: Write the test**

`tests/test_banking.lua`:
```lua
local function loadBanking() Config = { Job = { name = 'roxwoodracing', label = 'Roxwood Raceway' } }; Banking = nil; dofile('integrations/banking.lua') end

TEST('Renewed-Banking: deposit/withdraw call the exports and log a transaction', function()
  RESET_STUB(); STUB.started = { ['Renewed-Banking'] = true }
  local bal, log = 2000, {}
  STUB.exports = { ['Renewed-Banking'] = {
    getAccountMoney = function(_, acc) return bal end,
    addAccountMoney = function(_, acc, amt) bal = bal + amt return true end,
    removeAccountMoney = function(_, acc, amt) if bal < amt then return false end bal = bal - amt return true end,
    handleTransaction = function(_, acc, title, amount, message, issuer, receiver, ttype) log[#log+1] = { acc, title, amount, ttype } end,
    CreateJobAccount = function(_, job, initial) return { id = job.name } end,
  } }
  loadBanking()
  EQ(Banking.Provider, 'Renewed-Banking')
  TRUTHY(Banking.EnsureAccount('roxwoodracing', 'Roxwood Raceway'))
  TRUTHY(Banking.Deposit('roxwoodracing', 500, 'Entry fee', 'Lobby X', 'Sam Rider')); EQ(bal, 2500)
  TRUTHY(Banking.Withdraw('roxwoodracing', 1000, 'Purse', '1st place', 'Sam Rider')); EQ(bal, 1500)
  FALSY(Banking.Withdraw('roxwoodracing', 9999, 'Purse', 'too much', 'Sam Rider')); EQ(bal, 1500)
  EQ(#log, 2); EQ(log[1][4], 'deposit'); EQ(log[2][4], 'withdraw')
end)

TEST('no banking: Deposit/Withdraw succeed as no-ops and balance is huge', function()
  RESET_STUB(); loadBanking()
  EQ(Banking.Provider, 'none')
  TRUTHY(Banking.Deposit('roxwoodracing', 5, 't', 'm', 'x'))
  TRUTHY(Banking.Withdraw('roxwoodracing', 5, 't', 'm', 'x'))
  TRUTHY(Banking.GetBalance('roxwoodracing') >= 1e9)
end)

TEST('Garages: jg present -> insert row with garage_id; absent -> garage column', function()
  RESET_STUB(); STUB.started = { ['jg-advancedgarages'] = true }
  Config = { Economy = { prizeGarage = 'Roxwood Raceway' } }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function() return 'ABC123' end }
  function GetPlayerIdentifierByType() return 'license:abc' end
  dofile('integrations/garages.lua')
  TRUTHY(Garages.GiveVehicle(7, 'sultan3', 'PRIZE123'))
  TRUTHY(STUB.queries[1].sql:find('garage_id'), 'uses garage_id column')
  EQ(STUB.queries[1].params[7], 'Roxwood Raceway')
  RESET_STUB(); dofile('integrations/garages.lua')
  Garages.GiveVehicle(7, 'sultan3', 'PRIZE123')
  TRUTHY(STUB.queries[1].sql:find('garage,'), 'plain garage column')
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL (Banking nil).

- [ ] **Step 3: Write integrations/banking.lua**

```lua
-- Society money. Renewed-Banking is the DPS backend; qb-banking is the fallback; 'none' means
-- fees/purses become plain player cash (spec section 4) and a warning is printed at boot.
Banking = {}
Banking.Provider = 'none'
if GetResourceState('Renewed-Banking') == 'started' or GetResourceState('Renewed-Banking') == 'starting' then
  Banking.Provider = 'Renewed-Banking'
elseif GetResourceState('qb-banking') == 'started' then
  Banking.Provider = 'qb-banking'
end
print(('[dps-roxwoodracing] banking: %s'):format(Banking.Provider))
if Banking.Provider == 'none' then
  print('[dps-roxwoodracing] WARNING: no society banking found; entry fees and purses fall back to player cash')
end

local function rb() return exports['Renewed-Banking'] end

function Banking.EnsureAccount(name, label)
  if Banking.Provider == 'Renewed-Banking' then
    local ok, res = pcall(function() return rb():CreateJobAccount({ name = name, label = label }, 0) end)
    if not ok then print('[dps-roxwoodracing] CreateJobAccount failed: ' .. tostring(res)) end
    return ok and res ~= nil
  elseif Banking.Provider == 'qb-banking' then
    pcall(function() exports['qb-banking']:CreateJobAccount(name, 0) end)
    return true
  end
  return true
end

function Banking.GetBalance(account)
  if Banking.Provider == 'Renewed-Banking' then
    local ok, v = pcall(function() return rb():getAccountMoney(account) end)
    return ok and tonumber(v) or 0
  elseif Banking.Provider == 'qb-banking' then
    local ok, v = pcall(function() return exports['qb-banking']:GetAccountBalance(account) end)
    return ok and tonumber(v) or 0
  end
  return 1e12 -- no ledger: never "short"
end

local function ledger(account, title, amount, message, issuer, receiver, ttype)
  if Banking.Provider ~= 'Renewed-Banking' then return end
  pcall(function() rb():handleTransaction(account, title, amount, message, issuer, receiver, ttype) end)
end

function Banking.Deposit(account, amount, title, message, fromLabel)
  if amount <= 0 then return true end
  if Banking.Provider == 'Renewed-Banking' then
    local ok, res = pcall(function() return rb():addAccountMoney(account, amount) end)
    if not (ok and res) then return false end
    ledger(account, title, amount, message, fromLabel or 'Player', account, 'deposit')
    return true
  elseif Banking.Provider == 'qb-banking' then
    local ok, res = pcall(function() return exports['qb-banking']:AddMoney(account, amount, title) end)
    return ok and res ~= false
  end
  return true
end

function Banking.Withdraw(account, amount, title, message, toLabel)
  if amount <= 0 then return true end
  if Banking.Provider == 'Renewed-Banking' then
    if Banking.GetBalance(account) < amount then return false end
    local ok, res = pcall(function() return rb():removeAccountMoney(account, amount) end)
    if not (ok and res) then return false end
    ledger(account, title, amount, message, account, toLabel or 'Player', 'withdraw')
    return true
  elseif Banking.Provider == 'qb-banking' then
    if Banking.GetBalance(account) < amount then return false end
    local ok, res = pcall(function() return exports['qb-banking']:RemoveMoney(account, amount, title) end)
    return ok and res ~= false
  end
  return true
end

-- House mode: money is minted for the player but the ledger still shows the payment.
function Banking.LogOnly(account, amount, title, message, fromLabel, toLabel)
  ledger(account, title, amount, message, fromLabel or account, toLabel or 'Player', 'withdraw')
end
```

- [ ] **Step 4: Write integrations/garages.lua**

```lua
-- Prize-car delivery. With jg-advancedgarages the row carries garage_id (its column);
-- otherwise the stock qb/qbx 'garage' column.
Garages = {}
Garages.Provider = (GetResourceState('jg-advancedgarages') == 'started' or GetResourceState('jg-advancedgarages') == 'starting') and 'jg-advancedgarages' or 'none'
print(('[dps-roxwoodracing] garages: %s'):format(Garages.Provider))

function Garages.GiveVehicle(pid, model, plate)
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid then return false end
  local license = GetPlayerIdentifierByType(pid, 'license') or ''
  local garage = Config.Economy.prizeGarage or 'Roxwood Raceway'
  if Bridge.Framework == 'esx' then
    MySQL.insert.await('INSERT INTO owned_vehicles (owner, plate, vehicle, stored) VALUES (?, ?, ?, 1)',
      { cid, plate, json.encode({ model = joaat(model), plate = plate }) })
    return true
  end
  if Garages.Provider == 'jg-advancedgarages' then
    MySQL.insert.await(
      'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage_id, in_garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1)',
      { license, cid, model, joaat(model), '{}', plate, garage })
  else
    MySQL.insert.await(
      'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, 1)',
      { license, cid, model, joaat(model), '{}', plate, 'pillboxgarage' })
  end
  return true
end
```

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → `13 passed, 0 failed`.
```bash
git add integrations/banking.lua integrations/garages.lua tests/test_banking.lua
git commit -m "Server integrations: Renewed-Banking society account and jg-aware prize car"
```

---

### Task 6: Pure shared modules — validate, plates, tune, payouts

**Files:**
- Create: `shared/validate.lua`, `shared/plates.lua`, `shared/tune.lua`, `shared/payouts.lua`
- Test: `tests/test_shared.lua`

**Interfaces:**
- `Validate.CreateArgs(args, cfg) → ok:boolean, errKey:string|nil, clean:table` where `args = { name, track, laps, mode, class, tune }`; `clean.mode ∈ 'spec'|'open'`, `clean.class` is a key of `cfg.SpecClassKeys` (spec) or `cfg.OpenClasses` (open), `clean.tune` a key of `cfg.Tune`.
- `Plates.FromName(first, last, fallback, used) → string` (≤8 chars, unique within `used`).
- `Tune.ModsFor(preset, cfg) → { mods = {[slot]=index|'max'}, toggles = {[slot]=bool} }`.
- `Payouts.Compute(results, bestLapPid, economy, pool, balance) → payouts, purseCovered` where `payouts[pid] = { position=, participation=, bestLap=, pool=, total= }`, `purseCovered` false when `balance < purseTotal` (then position/participation/bestLap are zero and only pool pays).

- [ ] **Step 1: Write the test**

`tests/test_shared.lua`:
```lua
dofile('shared/validate.lua'); dofile('shared/plates.lua'); dofile('shared/tune.lua'); dofile('shared/payouts.lua')

local cfg = {
  Checkpoints = { Short_Track = {1,2,3} },
  OpenClasses = { Any = {}, Super = {} },
  Tune = { Stock = { mods = {}, toggles = {} }, Race = { mods = { [11] = 'max' }, toggles = { [18] = true } } },
  SpecClassKeys = { All = true, Super = true },
}

TEST('Validate.CreateArgs accepts a good spec request and defaults', function()
  local ok, err, c = Validate.CreateArgs({ name = 'Sam_1234', track = 'Short_Track', laps = 3 }, cfg)
  TRUTHY(ok, err); EQ(c.mode, 'spec'); EQ(c.class, 'All'); EQ(c.tune, 'Stock'); EQ(c.laps, 3)
end)
TEST('Validate.CreateArgs rejects bad name, track, laps, mode, class', function()
  local ok, err = Validate.CreateArgs({ name = 'bad name!', track = 'Short_Track', laps = 3 }, cfg); FALSY(ok); EQ(err, 'invalid_lobby_name')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Nope', laps = 3 }, cfg); FALSY(ok); EQ(err, 'invalid_track')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 11 }, cfg); FALSY(ok); EQ(err, 'invalid_laps')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'weird' }, cfg); FALSY(ok); EQ(err, 'invalid_mode')
  ok, err = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'open', class = 'Muscle' }, cfg); FALSY(ok); EQ(err, 'invalid_class')
  local ok2, _, c = Validate.CreateArgs({ name = 'ok', track = 'Short_Track', laps = 2, mode = 'open', class = 'Super', tune = 'Race' }, cfg)
  TRUTHY(ok2); EQ(c.tune, 'Stock', 'tune ignored for open')
end)

TEST('Plates.FromName sanitises, trims to 8, uniquifies', function()
  local used = {}
  EQ(Plates.FromName('Sam', "O'Rider", 'rock', used), 'SAMORIDE')
  EQ(Plates.FromName('Sam', "O'Rider", 'rock', used), 'SAMORID1')
  EQ(Plates.FromName(nil, nil, 'rock star', used), 'ROCKSTAR')
  EQ(Plates.FromName(nil, nil, '', used), 'RWR')
end)

TEST('Tune.ModsFor returns preset mods and empty for unknown', function()
  EQ(Tune.ModsFor('Race', cfg).mods[11], 'max'); TRUTHY(Tune.ModsFor('Race', cfg).toggles[18])
  EQ(next(Tune.ModsFor('Nope', cfg).mods), nil)
end)

local economy = { payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, poolSplit = { [1] = 60, [2] = 30, [3] = 10 } }
local results = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 } }

TEST('Payouts.Compute pays purse + pool when balance covers it', function()
  local p, covered = Payouts.Compute(results, 2, economy, 4000, 100000)
  TRUTHY(covered)
  EQ(p[1].position, 5000); EQ(p[1].participation, 500); EQ(p[1].bestLap, 0); EQ(p[1].pool, 2400); EQ(p[1].total, 7900)
  EQ(p[2].bestLap, 1000); EQ(p[2].pool, 1200); EQ(p[2].total, 3000 + 500 + 1000 + 1200)
  EQ(p[4].position, 0); EQ(p[4].pool, 0); EQ(p[4].total, 500)
  EQ(Payouts.PurseTotal(results, 2, economy), 5000 + 3000 + 1500 + 4 * 500 + 1000)
end)
TEST('Payouts.Compute pays pool only when the account is short', function()
  local p, covered = Payouts.Compute(results, 2, economy, 4000, 100)
  FALSY(covered)
  EQ(p[1].position, 0); EQ(p[1].participation, 0); EQ(p[2].bestLap, 0); EQ(p[1].pool, 2400); EQ(p[1].total, 2400)
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL (Validate nil).

- [ ] **Step 3: Write the four modules**

`shared/validate.lua`:
```lua
Validate = {}

---@return boolean ok, string|nil errKey, table clean
function Validate.CreateArgs(args, cfg)
  args = type(args) == 'table' and args or {}
  local clean = {}
  local name = args.name
  if type(name) ~= 'string' or #name < 1 or #name > 50 or name:find('[^%w_]') then return false, 'invalid_lobby_name', clean end
  clean.name = name
  if type(args.track) ~= 'string' or not cfg.Checkpoints[args.track] then return false, 'invalid_track', clean end
  clean.track = args.track
  local laps = tonumber(args.laps)
  if not laps or laps ~= math.floor(laps) or laps < 1 or laps > 10 then return false, 'invalid_laps', clean end
  clean.laps = laps
  local mode = args.mode or 'spec'
  if mode ~= 'spec' and mode ~= 'open' then return false, 'invalid_mode', clean end
  clean.mode = mode
  if mode == 'open' then
    local cls = args.class or 'Any'
    if type(cls) ~= 'string' or not cfg.OpenClasses[cls] then return false, 'invalid_class', clean end
    clean.class = cls
    clean.tune = 'Stock'
  else
    local cls = args.class or 'All'
    if type(cls) ~= 'string' or not (cfg.SpecClassKeys and cfg.SpecClassKeys[cls]) then return false, 'invalid_class', clean end
    clean.class = cls
    local tune = args.tune or 'Stock'
    if type(tune) ~= 'string' or not cfg.Tune[tune] then return false, 'invalid_tune', clean end
    clean.tune = tune
  end
  return true, nil, clean
end
```

`shared/plates.lua` (logic lifted from `makePlateFromPlayer`, framework calls removed):
```lua
Plates = {}

local function san(s)
  if not s then return '' end
  s = tostring(s):gsub('%s+', ''):upper():gsub('[^A-Z0-9]', '')
  return s
end

---@param first string|nil  @param last string|nil  @param fallback string|nil  @param used table|nil
function Plates.FromName(first, last, fallback, used)
  local candidates = {}
  if first or last then
    candidates[#candidates+1] = san((first or '') .. (last or ''))
    candidates[#candidates+1] = san((first and first:sub(1, 1) or '') .. (last or ''))
  end
  candidates[#candidates+1] = san(fallback or '')
  candidates[#candidates+1] = 'RWR'
  local str = 'RWR'
  for _, c in ipairs(candidates) do if #c > 0 then str = c break end end
  if #str > 8 then str = str:sub(1, 8) end
  if used then
    local base, suffix = str, 0
    while used[str] do
      suffix = suffix + 1
      local suf = tostring(suffix)
      str = base:sub(1, math.max(0, 8 - #suf)) .. suf
    end
    used[str] = true
  end
  return str
end
```

`shared/tune.lua`:
```lua
Tune = {}
function Tune.ModsFor(preset, cfg)
  local t = cfg.Tune and cfg.Tune[preset]
  if not t then return { mods = {}, toggles = {} } end
  return { mods = t.mods or {}, toggles = t.toggles or {} }
end
```

`shared/payouts.lua`:
```lua
Payouts = {}

local function purseFor(pos, pid, bestLapPid, eco)
  local position = eco.payouts[pos] or 0
  local participation = eco.participationReward or 0
  local bestLap = (pid == bestLapPid and eco.bestLapBonus) or 0
  return position, participation, bestLap
end

function Payouts.PurseTotal(results, bestLapPid, eco)
  local sum = 0
  for pos, e in ipairs(results) do
    local a, b, c = purseFor(pos, e.id, bestLapPid, eco)
    sum = sum + a + b + c
  end
  return sum
end

---@return table payouts (pid -> parts), boolean purseCovered
function Payouts.Compute(results, bestLapPid, eco, pool, balance)
  local covered = (balance or 0) >= Payouts.PurseTotal(results, bestLapPid, eco)
  local out = {}
  for pos, e in ipairs(results) do
    local position, participation, bestLap = 0, 0, 0
    if covered then position, participation, bestLap = purseFor(pos, e.id, bestLapPid, eco) end
    local pct = eco.poolSplit[pos] or 0
    local poolPay = math.floor((pool or 0) * pct / 100)
    out[e.id] = { position = position, participation = participation, bestLap = bestLap, pool = poolPay,
                  total = position + participation + bestLap + poolPay }
  end
  return out, covered
end
```

- [ ] **Step 4: Run tests, commit**

`./tools/check.sh` → `20 passed, 0 failed`.
```bash
git add shared tests/test_shared.lua
git commit -m "Shared pure modules: lobby validation, plates, tune presets, payout maths"
```

---

### Task 7: Rewards on the society account

**Files:**
- Create: `server/rewards.lua`
- Modify: `server/race.lua` (delete `GrantRewards`, `DistributePrizePool`, `ChargeEntryFee`, `RefundEntryFee`; call `Rewards.*`), `config/economy.lua` (delete `Config.Rewards`, `Config.EntryFee`)
- Test: `tests/test_rewards.lua`

**Interfaces:**
- Consumes: `Banking.*` (Task 5), `Payouts.*` (Task 6), `Bridge.*` (Task 3), `Garages.GiveVehicle` (Task 5).
- Produces: `Rewards.ChargeEntryFee(pid, lobbyName) → bool`, `Rewards.RefundEntryFee(pid, lobbyName)`, `Rewards.Settle(lob, results, bestLapPid) → payouts, purseCovered` (pays everyone, sends `client:rewardNotify`), `Rewards.FeeAmount() → number`.

- [ ] **Step 1: Write the test**

`tests/test_rewards.lua`:
```lua
local function setup(provider, balance)
  RESET_STUB()
  Config = { Job = { name = 'roxwoodracing', label = 'Roxwood Raceway' },
             Economy = { purseSource = 'society', entryFee = { enabled = true, amount = 1000 }, poolSplit = { [1] = 60, [2] = 30, [3] = 10 },
                         payouts = { [1] = 5000, [2] = 3000, [3] = 1500 }, participationReward = 500, bestLapBonus = 1000, moneyType = 'cash' } }
  local cash = { [1] = 2000, [2] = 50 }
  Bridge = { Framework = 'qbx',
    GetPlayerIdentifier = function(pid) return cash[pid] and ('CID' .. pid) or nil end,
    GetPlayerName = function(pid) return 'P' .. pid end,
    GetMoney = function(pid) return cash[pid] or 0 end,
    RemoveMoney = function(pid, _, amt) if (cash[pid] or 0) < amt then return false end cash[pid] = cash[pid] - amt return true end,
    AddMoney = function(pid, _, amt) cash[pid] = (cash[pid] or 0) + amt return true end }
  local society = balance
  Banking = { Provider = provider, GetBalance = function() return society end,
    Deposit = function(_, amt) society = society + amt return true end,
    Withdraw = function(_, amt) if society < amt then return false end society = society - amt return true end,
    LogOnly = function() end }
  Garages = { GiveVehicle = function() return true end }
  dofile('shared/payouts.lua'); dofile('server/rewards.lua')
  return cash, function() return society end
end

TEST('entry fee moves cash into the society account and refunds back', function()
  local cash, soc = setup('Renewed-Banking', 0)
  TRUTHY(Rewards.ChargeEntryFee(1, 'L')); EQ(cash[1], 1000); EQ(soc(), 1000)
  FALSY(Rewards.ChargeEntryFee(2, 'L'), 'broke player')
  Rewards.RefundEntryFee(1, 'L'); EQ(cash[1], 2000); EQ(soc(), 0)
end)

TEST('Settle pays purse from society when covered', function()
  local cash, soc = setup('Renewed-Banking', 50000)
  local lob = { players = { 1, 2 }, prizePool = 2000, name = 'L' }
  local results = { { id = 1 }, { id = 2 } }
  local p, covered = Rewards.Settle(lob, results, 1)
  TRUTHY(covered)
  EQ(cash[1], 2000 + 5000 + 500 + 1000 + 1200)
  EQ(cash[2], 50 + 3000 + 500 + 600)
  EQ(soc(), 50000 - (5000 + 500 + 1000 + 1200) - (3000 + 500 + 600))
  EQ(STUB.clientEvents[1].name, 'dps-roxwoodracing:client:rewardNotify')
end)

TEST('Settle pays pool only when society is short', function()
  local cash, soc = setup('Renewed-Banking', 2000)
  local lob = { players = { 1, 2 }, prizePool = 2000, name = 'L' }
  local p, covered = Rewards.Settle(lob, results or { { id = 1 }, { id = 2 } }, 1)
  FALSY(covered)
  EQ(cash[1], 2000 + 1200); EQ(cash[2], 50 + 600); EQ(soc(), 200)
end)

TEST('house mode mints the purse and leaves the society untouched', function()
  local cash, soc = setup('Renewed-Banking', 0)
  Config.Economy.purseSource = 'house'
  local lob = { players = { 1 }, prizePool = 0, name = 'L' }
  local p, covered = Rewards.Settle(lob, { { id = 1 } }, 1)
  TRUTHY(covered); EQ(cash[1], 2000 + 5000 + 500 + 1000); EQ(soc(), 0)
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL (Rewards nil).

- [ ] **Step 3: Write server/rewards.lua**

```lua
-- Money in and out of the raceway. Every path goes through Banking so the ledger is the truth.
Rewards = {}

local function account() return Config.Job.name end
local function eco() return Config.Economy end

function Rewards.FeeAmount()
  local f = eco().entryFee
  return (f and f.enabled and f.amount) or 0
end

local function notify(pid, msgKey, ...)
  TriggerClientEvent('dps-roxwoodracing:client:notify', pid, Config.Job.label, Locale(msgKey, ...), 'inform')
end

function Rewards.ChargeEntryFee(pid, lobbyName)
  local amount = Rewards.FeeAmount()
  if amount <= 0 then return true end
  if not Bridge.Framework then return true end
  if Bridge.GetMoney(pid, eco().moneyType) < amount then
    TriggerClientEvent('dps-roxwoodracing:client:notify', pid, Config.Job.label, Locale('entry_fee_insufficient', amount), 'error')
    return false
  end
  if not Bridge.RemoveMoney(pid, eco().moneyType, amount, 'roxwoodracing-entryfee') then return false end
  Banking.Deposit(account(), amount, 'Entry fee', ('Lobby %s'):format(tostring(lobbyName)), Bridge.GetPlayerName(pid))
  notify(pid, 'entry_fee_charged', amount)
  return true
end

function Rewards.RefundEntryFee(pid, lobbyName)
  local amount = Rewards.FeeAmount()
  if amount <= 0 or not Bridge.Framework then return end
  if not Banking.Withdraw(account(), amount, 'Entry fee refund', ('Lobby %s'):format(tostring(lobbyName)), Bridge.GetPlayerName(pid)) then
    return -- account drained by staff meanwhile; nothing to refund from
  end
  Bridge.AddMoney(pid, eco().moneyType, amount, 'roxwoodracing-entryfee-refund')
  notify(pid, 'entry_fee_refunded', amount)
end

local function payFromSource(pid, amount, title, message)
  if amount <= 0 then return true end
  if eco().purseSource == 'house' then
    Banking.LogOnly(account(), amount, title, message, account(), Bridge.GetPlayerName(pid))
    return Bridge.AddMoney(pid, eco().moneyType, amount, 'roxwoodracing-' .. title:lower():gsub('%s', '-'))
  end
  if not Banking.Withdraw(account(), amount, title, message, Bridge.GetPlayerName(pid)) then return false end
  return Bridge.AddMoney(pid, eco().moneyType, amount, 'roxwoodracing-' .. title:lower():gsub('%s', '-'))
end

---@param lob table lobby (uses prizePool, name)
---@param results table sorted results { {id=}, ... }
---@param bestLapPid number|nil
---@return table payouts, boolean purseCovered
function Rewards.Settle(lob, results, bestLapPid)
  if not Bridge.Framework then return {}, true end
  local balance = eco().purseSource == 'house' and math.huge or Banking.GetBalance(account())
  local payouts, covered = Payouts.Compute(results, bestLapPid, eco(), lob.prizePool or 0, balance)
  local labelFor = { [1] = '1st', [2] = '2nd', [3] = '3rd' }
  for pos, entry in ipairs(results) do
    local pid, p = entry.id, payouts[entry.id]
    if Bridge.GetPlayerIdentifier(pid) then
      local msg = ('Lobby %s, %s'):format(tostring(lob.name), labelFor[pos] or (pos .. 'th'))
      payFromSource(pid, p.position, 'Podium purse', msg)
      payFromSource(pid, p.participation, 'Show-up bonus', msg)
      payFromSource(pid, p.bestLap, 'Fastest lap', msg)
      -- Pool money is the racers' own buy-ins parked in the account; always paid.
      if p.pool > 0 then
        if Banking.Withdraw(account(), p.pool, 'Prize pool', msg, Bridge.GetPlayerName(pid)) then
          Bridge.AddMoney(pid, eco().moneyType, p.pool, 'roxwoodracing-prizepool')
        end
      end
      local vehiclePrize = nil
      if pos == 1 and eco().vehiclePrize and covered then
        vehiclePrize = eco().vehiclePrize
        Garages.GiveVehicle(pid, vehiclePrize, 'PRIZE' .. math.random(100, 999))
      end
      TriggerClientEvent('dps-roxwoodracing:client:rewardNotify', pid, {
        positionPayout = p.position, positionLabel = labelFor[pos] or (pos .. 'th'),
        participation = p.participation, bestLapBonus = p.bestLap, poolPayout = p.pool,
        vehiclePrize = vehiclePrize, totalPayout = p.total, purseCovered = covered,
      })
    end
  end
  return payouts, covered
end

CreateThread(function()
  Wait(1000)
  Banking.EnsureAccount(Config.Job.name, Config.Job.label)
end)
```
Add `Locale = Locale or function(k) return k end` to `tests/stubs.lua`.

- [ ] **Step 4: Wire server/race.lua to it**

In `server/race.lua`:
- Delete the functions `GrantRewards` (old 106–176), `DistributePrizePool` (181–196), `ChargeEntryFee` (271–284), `RefundEntryFee` (286–293).
- `createLobby`: `if not ChargeEntryFee(src) then return end` → `if not Rewards.ChargeEntryFee(src, lobbyName) then return end`; `local entryFeeAmount = ...` → `local entryFeeAmount = Rewards.FeeAmount()`. Same two substitutions in `joinLobby`.
- `leaveLobby`: `RefundEntryFee(src)` → `Rewards.RefundEntryFee(src, name)`; `RefundEntryFee(player)` → `Rewards.RefundEntryFee(player, name)`; `local entryFeeAmount = ...` → `Rewards.FeeAmount()`.
- In `lapPassed` all-finished block: replace the `entry.payout` computation loop (old 1190–1205) with:
```lua
      for pos, entry in ipairs(results) do
        entry.position = pos
        entry.isBestLap = (entry.id == bestLapPlayer)
      end
```
  and replace `GrantRewards(lob, results, lobbyName)` + `DistributePrizePool(lob, results)` with:
```lua
      lob.name = lobbyName
      local payouts, purseCovered = Rewards.Settle(lob, results, bestLapPlayer)
      for _, entry in ipairs(results) do entry.payout = payouts[entry.id] and payouts[entry.id].total or 0 end
```
  Move the `finalRanking` broadcast loop (old 1224–1232) to **after** this so `entry.payout` is real, and add `purseCovered = purseCovered` to its payload.
- `SaveRaceStats(...)` call keeps `totalEarnings = entry.payout`.

Delete `Config.Rewards` and `Config.EntryFee` from `config/economy.lua`. `grep -rn "Config.Rewards\|Config.EntryFee" --include=*.lua .` must print nothing.

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → `24 passed, 0 failed`.
```bash
git add server/rewards.lua server/race.lua config/economy.lua tests
git commit -m "Rewards: entry fees, pool and purse through the roxwoodracing society account"
```

---

### Task 8: Stats table rename and mode counters

**Files:**
- Create: `server/stats.lua`
- Modify: `server/race.lua` (delete table create block and `SaveRaceStats`, `getPlayerStats` callback; call `Stats.Save`), `server/leaderboard.lua` (table name in `GetTopBestTimes`)
- Test: `tests/test_stats.lua`

**Interfaces:**
- Produces: `Stats.TABLE = 'dps_roxwoodracing_stats'`, `Stats.Migrate()` (rename or create), `Stats.Save(pid, position, track, bestLap, earnings, mode)`, `Stats.MergeBestLap(bestLaps, track, lap) → bestLaps, newRecord:boolean`, callback `dps-roxwoodracing:getPlayerStats`.

- [ ] **Step 1: Write the test**

`tests/test_stats.lua`:
```lua
TEST('MergeBestLap records only faster laps', function()
  RESET_STUB(); Config = { Stats = { enabled = true, showAfterRace = false } }; Bridge = { GetPlayerIdentifier = function() return 'C1' end }
  dofile('server/stats.lua')
  local bl, rec = Stats.MergeBestLap({ Short_Track = 50000 }, 'Short_Track', 48000); TRUTHY(rec); EQ(bl.Short_Track, 48000)
  bl, rec = Stats.MergeBestLap(bl, 'Short_Track', 49000); FALSY(rec); EQ(bl.Short_Track, 48000)
  bl, rec = Stats.MergeBestLap(bl, 'Long_Track', 0); FALSY(rec)
end)

TEST('Migrate renames the old table when only it exists', function()
  RESET_STUB(); Config = { Stats = { enabled = true } }; Bridge = {}
  STUB.scalar = 1 -- first scalar: old exists; second: new missing handled by sequence below
  local seq, i = { 1, 0 }, 0
  MySQL.scalar.await = function(sql, params) i = i + 1; STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return seq[i] end
  dofile('server/stats.lua'); Stats.Migrate()
  local renamed = false
  for _, q in ipairs(STUB.queries) do if q.sql:find('RENAME TABLE') then renamed = true end end
  TRUTHY(renamed)
end)

TEST('Save upserts with mode counters', function()
  RESET_STUB(); Config = { Stats = { enabled = true, showAfterRace = false } }; Bridge = { GetPlayerIdentifier = function() return 'C1' end }
  STUB.row = { total_races = 2, wins = 1, best_laps = '{"Short_Track":50000}' }
  dofile('server/stats.lua')
  Stats.Save(7, 1, 'Short_Track', 48000, 7900, 'open')
  local q = STUB.queries[#STUB.queries]
  TRUTHY(q.sql:find('open_wins'), 'open_wins column in upsert')
  EQ(q.params[1], 'C1')
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL.

- [ ] **Step 3: Write server/stats.lua**

```lua
Stats = {}
Stats.TABLE = 'dps_roxwoodracing_stats'

local function tableExists(name)
  local n = MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name })
  return (tonumber(n) or 0) > 0
end

function Stats.Migrate()
  if not (Config.Stats and Config.Stats.enabled) then return end
  local oldExists, newExists = tableExists('speedway_stats'), tableExists(Stats.TABLE)
  if oldExists and not newExists then
    MySQL.query.await(('RENAME TABLE speedway_stats TO %s'):format(Stats.TABLE))
    print('[dps-roxwoodracing] stats: renamed speedway_stats -> ' .. Stats.TABLE)
  end
  MySQL.query.await(([[
    CREATE TABLE IF NOT EXISTS %s (
      citizenid VARCHAR(50) NOT NULL,
      total_races INT DEFAULT 0,
      wins INT DEFAULT 0,
      top3 INT DEFAULT 0,
      total_earnings INT DEFAULT 0,
      best_laps JSON DEFAULT '{}',
      last_race TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (citizenid)
    )]]):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS spec_wins INT DEFAULT 0'):format(Stats.TABLE))
  MySQL.query.await(('ALTER TABLE %s ADD COLUMN IF NOT EXISTS open_wins INT DEFAULT 0'):format(Stats.TABLE))
  print('[dps-roxwoodracing] stats: table ready')
end

function Stats.MergeBestLap(bestLaps, track, lap)
  bestLaps = bestLaps or {}
  if lap and lap > 0 and (not bestLaps[track] or lap < bestLaps[track]) then
    bestLaps[track] = lap
    return bestLaps, true
  end
  return bestLaps, false
end

function Stats.Save(pid, position, track, bestLap, earnings, mode)
  if not (Config.Stats and Config.Stats.enabled) then return end
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid then return end
  local isWin = position == 1 and 1 or 0
  local isTop3 = position <= 3 and 1 or 0
  local specWin = (isWin == 1 and mode ~= 'open') and 1 or 0
  local openWin = (isWin == 1 and mode == 'open') and 1 or 0
  earnings = earnings or 0
  local existing = MySQL.single.await(('SELECT total_races, wins, best_laps FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  local bestLaps, prevRaces, prevWins = {}, 0, 0
  if existing then
    bestLaps = json.decode(existing.best_laps or '{}') or {}
    prevRaces, prevWins = existing.total_races or 0, existing.wins or 0
  end
  local newRecord
  bestLaps, newRecord = Stats.MergeBestLap(bestLaps, track, bestLap)
  local encoded = json.encode(bestLaps)
  MySQL.query.await(([[
    INSERT INTO %s (citizenid, total_races, wins, top3, total_earnings, best_laps, spec_wins, open_wins, last_race)
    VALUES (?, 1, ?, ?, ?, ?, ?, ?, NOW())
    ON DUPLICATE KEY UPDATE
      total_races = total_races + 1, wins = wins + ?, top3 = top3 + ?, total_earnings = total_earnings + ?,
      best_laps = ?, spec_wins = spec_wins + ?, open_wins = open_wins + ?, last_race = NOW()]]):format(Stats.TABLE),
    { cid, isWin, isTop3, earnings, encoded, specWin, openWin, isWin, isTop3, earnings, encoded, specWin, openWin })
  if Config.Stats.showAfterRace then
    TriggerClientEvent('dps-roxwoodracing:client:statsNotify', pid, {
      wins = prevWins + isWin, totalRaces = prevRaces + 1, bestLap = bestLaps[track], newRecord = newRecord and bestLap or nil,
    })
  end
end

lib.callback.register('dps-roxwoodracing:getPlayerStats', function(source)
  local cid = Bridge.GetPlayerIdentifier(source)
  if not cid then return nil end
  local row = MySQL.single.await(('SELECT * FROM %s WHERE citizenid = ?'):format(Stats.TABLE), { cid })
  if not row then return nil end
  row.best_laps = json.decode(row.best_laps or '{}') or {}
  return row
end)

CreateThread(Stats.Migrate)
```
Note the test stub's `CreateThread` runs immediately, so `Stats.Migrate` runs at dofile; the second test accounts for that by pre-seeding the scalar sequence before `dofile`.

- [ ] **Step 4: Wire the callers**

- `server/race.lua`: delete the table-create block (old 78–94), `SaveRaceStats` (201–254), the `getPlayerStats` callback (259–266). Replace `SaveRaceStats(pidLocal, posLocal, lob.track, bestLapLocal, totalEarnings)` with `Stats.Save(pidLocal, posLocal, lob.track, bestLapLocal, totalEarnings, lob.mode)`.
- `server/leaderboard.lua`: `FROM speedway_stats` → `FROM dps_roxwoodracing_stats`. Its `Bridge.GetAllPlayersWithIdentifier()` use (name resolution for idle board) becomes `Bridge.GetPlayerNameFromDB(citizenid)` per row, cached in a local table.

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → `27 passed, 0 failed`.
```bash
git add server tests/test_stats.lua
git commit -m "Stats: rename to dps_roxwoodracing_stats with migration and spec/open win counters"
```

---

### Task 9: Extract ranking and results into a pure module

**Files:**
- Create: `shared/ranking.lua`
- Modify: `server/race.lua` (`updateProgress` sort and `lapPassed` results build call the module)
- Test: `tests/test_ranking.lua`

**Interfaces:**
- Produces: `Ranking.SortBoard(board, checkpointProgress)` sorts `board = { {id, lap, dist}, ... }` in place by lap desc, checkpoint desc, dist desc; `Ranking.BuildResults(players, lapTimes, gridOrder, nameOf) → results, bestLapPid, mostImprovedPid` where each result is `{ id, name, time, bestLap, lapTimes, position, gridPosition, isBestLap, isMostImproved }` sorted by total time.

- [ ] **Step 1: Write the test**

`tests/test_ranking.lua`:
```lua
dofile('shared/ranking.lua')

TEST('SortBoard: lap beats checkpoint beats distance', function()
  local board = { { id = 1, lap = 0, dist = 900 }, { id = 2, lap = 1, dist = 10 }, { id = 3, lap = 0, dist = 100 } }
  Ranking.SortBoard(board, { [1] = 2, [3] = 3 })
  EQ(board[1].id, 2); EQ(board[2].id, 3); EQ(board[3].id, 1)
end)

TEST('BuildResults sorts by total, flags best lap and most improved', function()
  local lapTimes = { [1] = { 30000, 31000 }, [2] = { 29000, 33000 }, [3] = { 40000, 40000 } }
  local results, bestPid, improvedPid = Ranking.BuildResults({ 1, 2, 3 }, lapTimes, { [1] = 3, [2] = 1, [3] = 2 }, function(pid) return 'P' .. pid end)
  EQ(results[1].id, 1); EQ(results[1].time, 61000); EQ(results[1].position, 1); EQ(results[1].gridPosition, 3)
  EQ(bestPid, 2); TRUTHY(results[2].isBestLap); EQ(results[2].bestLap, 29000)
  EQ(improvedPid, 1); TRUTHY(results[1].isMostImproved); FALSY(results[2].isMostImproved)
  EQ(results[3].name, 'P3')
end)

TEST('BuildResults with no laps gives zero times and no badges', function()
  local results, bestPid, improvedPid = Ranking.BuildResults({ 5 }, {}, {}, function() return 'x' end)
  EQ(results[1].time, 0); EQ(results[1].bestLap, 0); EQ(bestPid, nil); EQ(improvedPid, nil)
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL.

- [ ] **Step 3: Write shared/ranking.lua** (logic lifted from `updateProgress` and the all-finished block of `lapPassed`)

```lua
Ranking = {}

function Ranking.SortBoard(board, checkpointProgress)
  table.sort(board, function(a, b)
    if a.lap ~= b.lap then return a.lap > b.lap end
    local acp, bcp = checkpointProgress[a.id] or 0, checkpointProgress[b.id] or 0
    if acp ~= bcp then return acp > bcp end
    return a.dist > b.dist
  end)
  return board
end

function Ranking.BuildResults(players, lapTimes, gridOrder, nameOf)
  local results, globalBest, bestPid = {}, math.huge, nil
  for _, pid in ipairs(players) do
    local sum, best = 0, math.huge
    for _, t in ipairs(lapTimes[pid] or {}) do
      sum = sum + t
      if t < best then best = t end
    end
    if best < globalBest then globalBest, bestPid = best, pid end
    if best == math.huge then best = 0 end
    results[#results+1] = { id = pid, name = nameOf(pid), time = sum, bestLap = best, lapTimes = lapTimes[pid] or {} }
  end
  table.sort(results, function(a, b) return a.time < b.time end)
  local improvedPid, improvedGain = nil, 0
  for pos, e in ipairs(results) do
    e.position = pos
    e.gridPosition = (gridOrder and gridOrder[e.id]) or pos
    e.isBestLap = (e.id == bestPid)
    local gain = e.gridPosition - pos
    if gain > improvedGain then improvedGain, improvedPid = gain, e.id end
  end
  for _, e in ipairs(results) do e.isMostImproved = (e.id == improvedPid) end
  return results, bestPid, improvedPid
end
```

- [ ] **Step 4: Wire server/race.lua**

- In `updateProgress`, replace the `table.sort(board, function(a, b) ... end)` block (old 936–946) with `Ranking.SortBoard(board, lob.checkpointProgress)`.
- In `lapPassed` all-finished block, replace everything from `local results = {}` through the `isMostImproved` loop (old 1166–1221, minus the payout part already replaced in Task 7) with:
```lua
      local results, bestLapPlayer, mostImprovedId = Ranking.BuildResults(lob.players, lob.lapTimes, lob.gridOrder,
        function(pid) return Bridge.GetPlayerName(pid) or ('Player ' .. pid) end)
```
  and keep the `Rewards.Settle` + payout stamping from Task 7 right after it.

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → `30 passed, 0 failed`.
```bash
git add shared/ranking.lua server/race.lua tests/test_ranking.lua
git commit -m "Extract ranking sort and results build into a pure shared module"
```

---

### Task 10: Lobby modes on the server — Spec catalogue, Open join, tune payload

**Files:**
- Create: `server/lobbies.lua`
- Modify: `server/race.lua` (createLobby/joinLobby/startRace/selectedVehicle/SpawnRaceVehicles/finish teleport)
- Test: `tests/test_lobbies.lua`

**Interfaces:**
- Consumes: `Validate.CreateArgs`, `Plates.FromName`, `Rewards.*`, `Ranking.*`.
- Produces: `Lobbies.SpecCatalogue() → { classes = { [key] = { label, vehicles = { {model, label}, ... } } }, order = { key, ... } }` built from `exports.qbx_core:GetVehiclesByName()` (fallback `Config.SpecFallbackVehicles`), cached; `Config.SpecClassKeys` populated from it at boot (`All` + one key per class + preset keys). `Lobbies.IsModelAllowed(classKey, model) → bool`. `Lobbies.VerifyOwnedVehicle(pid, plate) → bool` (query `player_vehicles`/`owned_vehicles`). Callback `dps-roxwoodracing:getSpecCatalogue`.
- Lobby record gains: `mode`, `class`, `tune`, `vehicles = { [pid] = { netId=, plate= } }` (open mode).
- Client event contract changes: `createLobby(args)` takes one table `{ name, track, laps, mode, class, tune }`; `joinLobby(lobbyName, vehicle)` where `vehicle = { netId, plate, class } | nil`; `prepareStart` payload gains `mode`, `tune`, `keepVehicle`; `client:finishTeleport(coords, keepVehicle)`.

- [ ] **Step 1: Write the test**

`tests/test_lobbies.lua`:
```lua
local function load()
  RESET_STUB(); STUB.started = { qbx_core = true }
  Config = { SpecFallbackVehicles = { { model = 'sultan3', label = 'Sultan RS Classic' } },
             SpecPresets = { Super = { label = 'Super Cars', description = '', vehicles = { 'krieger' } } },
             SpecClassLabels = { [6] = 'Sports', [7] = 'Super' }, OpenClasses = { Any = { classes = nil }, Super = { classes = { [7] = true } } } }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function() return 'C1' end }
  STUB.exports = { qbx_core = { GetVehiclesByName = function() return {
    krieger = { name = 'Krieger', category = 'super', model = 'krieger' },
    sultan3 = { name = 'Sultan RS Classic', category = 'sports', model = 'sultan3' },
    ambulance = { name = 'Ambulance', category = 'emergency', model = 'ambulance' },
  } end } }
  dofile('server/lobbies.lua')
end

TEST('SpecCatalogue groups registry vehicles by category and skips emergency/service', function()
  load()
  local cat = Lobbies.SpecCatalogue()
  TRUTHY(cat.classes.All); EQ(#cat.classes.All.vehicles, 2)
  EQ(cat.classes.Super.vehicles[1].model, 'krieger')
  TRUTHY(Config.SpecClassKeys.All); TRUTHY(Config.SpecClassKeys.Sports); TRUTHY(Config.SpecClassKeys.Super)
  TRUTHY(Lobbies.IsModelAllowed('All', 'sultan3')); TRUTHY(Lobbies.IsModelAllowed('Super', 'krieger')); FALSY(Lobbies.IsModelAllowed('Super', 'sultan3'))
  FALSY(Lobbies.IsModelAllowed('All', 'ambulance'))
end)

TEST('SpecCatalogue falls back to config list without a registry', function()
  load(); STUB.exports = {}; Lobbies._catalogue = nil
  local cat = Lobbies.SpecCatalogue()
  EQ(#cat.classes.All.vehicles, 1); EQ(cat.classes.All.vehicles[1].model, 'sultan3')
end)

TEST('VerifyOwnedVehicle checks the plate against the citizenid', function()
  load(); STUB.scalar = 1
  TRUTHY(Lobbies.VerifyOwnedVehicle(7, 'SAM123'))
  EQ(STUB.queries[#STUB.queries].params[1], 'SAM123'); EQ(STUB.queries[#STUB.queries].params[2], 'C1')
  STUB.scalar = 0; FALSY(Lobbies.VerifyOwnedVehicle(7, 'NOPE'))
end)

TEST('OpenClassAllows uses GetVehicleClass ids', function()
  load()
  TRUTHY(Lobbies.OpenClassAllows('Any', 3)); TRUTHY(Lobbies.OpenClassAllows('Super', 7)); FALSY(Lobbies.OpenClassAllows('Super', 6))
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL.

- [ ] **Step 3: Write server/lobbies.lua**

```lua
-- Spec catalogue (any registered car, grouped by class) and Open-mode ownership checks.
Lobbies = {}
Lobbies._catalogue = nil

local skipCategories = { emergency = true, service = true, military = true, utility = true, commercial = true,
                         industrial = true, trailers = true, boats = true, helicopters = true, planes = true, cycles = true, trains = true }
local categoryLabel = { compacts = 'Compacts', sedans = 'Sedans', suvs = 'SUVs', coupes = 'Coupes', muscle = 'Muscle',
                        sportsclassics = 'Sports Classics', sports = 'Sports', super = 'Super', motorcycles = 'Motorcycles',
                        offroad = 'Off-road', vans = 'Vans', pickups = 'Pickups', openwheel = 'Open Wheel', race = 'Race' }

local function registry()
  if Bridge.Framework == 'qbx' or Bridge.Framework == 'qb' then
    local ok, v = pcall(function()
      local res = Bridge.Framework == 'qbx' and 'qbx_core' or 'qb-core'
      return exports[res]:GetVehiclesByName()
    end)
    if ok and type(v) == 'table' and next(v) then return v end
  end
  return nil
end

function Lobbies.SpecCatalogue()
  if Lobbies._catalogue then return Lobbies._catalogue end
  local classes, order = { All = { label = 'Open class (any car)', vehicles = {} } }, { 'All' }
  local reg = registry()
  if reg then
    local models = {}
    for model, v in pairs(reg) do models[#models+1] = { model = model, label = v.name or model, category = (v.category or 'other'):lower() } end
    table.sort(models, function(a, b) return a.label < b.label end)
    for _, v in ipairs(models) do
      if not skipCategories[v.category] then
        local key = categoryLabel[v.category] and categoryLabel[v.category]:gsub('[^%w]', '') or 'Other'
        if not classes[key] then classes[key] = { label = categoryLabel[v.category] or 'Other', vehicles = {} }; order[#order+1] = key end
        classes[key].vehicles[#classes[key].vehicles+1] = { model = v.model, label = v.label }
        classes.All.vehicles[#classes.All.vehicles+1] = { model = v.model, label = v.label }
      end
    end
  else
    print('[dps-roxwoodracing] WARNING: no vehicle registry; spec menu uses Config.SpecFallbackVehicles')
    for _, v in ipairs(Config.SpecFallbackVehicles or {}) do classes.All.vehicles[#classes.All.vehicles+1] = { model = v.model, label = v.label } end
  end
  -- Named presets from config (only models the registry knows, or all when no registry)
  local known = {}
  for _, v in ipairs(classes.All.vehicles) do known[v.model:lower()] = v end
  for key, preset in pairs(Config.SpecPresets or {}) do
    local list = {}
    for _, m in ipairs(preset.vehicles or {}) do
      local v = known[m:lower()]
      if v then list[#list+1] = v elseif not reg then list[#list+1] = { model = m, label = m } end
    end
    if #list > 0 then
      local k = 'Preset' .. key
      classes[k] = { label = preset.label or key, vehicles = list }; order[#order+1] = k
    else
      print(('[dps-roxwoodracing] preset %s has no registered vehicles; skipped'):format(key))
    end
  end
  Config.SpecClassKeys = {}
  for k in pairs(classes) do Config.SpecClassKeys[k] = true end
  Lobbies._catalogue = { classes = classes, order = order }
  return Lobbies._catalogue
end

function Lobbies.IsModelAllowed(classKey, model)
  local cat = Lobbies.SpecCatalogue()
  local cls = cat.classes[classKey]
  if not cls or type(model) ~= 'string' then return false end
  local m = model:lower()
  for _, v in ipairs(cls.vehicles) do if v.model:lower() == m then return true end end
  return false
end

function Lobbies.OpenClassAllows(classKey, vehicleClassId)
  local oc = Config.OpenClasses[classKey]
  if not oc then return false end
  if not oc.classes then return true end
  return oc.classes[vehicleClassId] == true
end

function Lobbies.VerifyOwnedVehicle(pid, plate)
  local cid = Bridge.GetPlayerIdentifier(pid)
  if not cid or type(plate) ~= 'string' then return false end
  plate = plate:gsub('^%s+', ''):gsub('%s+$', '')
  local n
  if Bridge.Framework == 'esx' then
    n = MySQL.scalar.await('SELECT COUNT(*) FROM owned_vehicles WHERE plate = ? AND owner = ?', { plate, cid })
  else
    n = MySQL.scalar.await('SELECT COUNT(*) FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, cid })
  end
  return (tonumber(n) or 0) > 0
end

lib.callback.register('dps-roxwoodracing:getSpecCatalogue', function() return Lobbies.SpecCatalogue() end)
lib.callback.register('dps-roxwoodracing:getOpenClasses', function()
  local out = {}
  for k, v in pairs(Config.OpenClasses) do out[#out+1] = { value = k, label = v.label } end
  table.sort(out, function(a, b) if a.value == 'Any' then return true elseif b.value == 'Any' then return false end return a.label < b.label end)
  return out
end)

CreateThread(function() Wait(500); Lobbies.SpecCatalogue() end)
```

- [ ] **Step 4: Port server/race.lua to modes**

Apply these edits to `server/race.lua`:

1. Delete `VALID_TRACKS`, `VALID_CLASSES`, `VALID_MODELS` (old 41–48) and `makePlateFromPlayer` (316–362).
2. `createLobby` becomes:
```lua
RegisterNetEvent('dps-roxwoodracing:createLobby', function(args)
  local src = source
  if RateLimit(src, 'createLobby', 2000) then return end
  local ok, errKey, c = Validate.CreateArgs(args, Config)
  if not ok then ServerNotify(src, Config.Job.label, Locale(errKey), 'error') return end
  for _, existing in pairs(lobbies) do
    if existing.track == c.track then ServerNotify(src, Config.Job.label, Locale('track_in_use'), 'error') return end
  end
  if lobbies[c.name] then ServerNotify(src, Config.Job.label, Locale('lobby_exists'), 'error') return end
  if c.mode == 'open' then
    local veh = args.vehicle
    if type(veh) ~= 'table' or not veh.plate then ServerNotify(src, Config.Job.label, Locale('open_need_vehicle'), 'error') return end
    if not Lobbies.VerifyOwnedVehicle(src, veh.plate) then ServerNotify(src, Config.Job.label, Locale('open_not_owner'), 'error') return end
    if not Lobbies.OpenClassAllows(c.class, tonumber(veh.class)) then ServerNotify(src, Config.Job.label, Locale('open_wrong_class', Config.OpenClasses[c.class].label), 'error') return end
  end
  if not Rewards.ChargeEntryFee(src, c.name) then return end
  lobbies[c.name] = {
    name = c.name, owner = src, track = c.track, laps = c.laps, mode = c.mode, class = c.class, tune = c.tune,
    players = { src }, vehicles = {}, checkpointProgress = {}, isStarted = false, lapProgress = {}, finished = {},
    lapTimes = {}, startTime = {}, progress = {}, prizePool = Rewards.FeeAmount(),
  }
  if c.mode == 'open' then lobbies[c.name].vehicles[src] = { netId = tonumber(args.vehicle.netId), plate = args.vehicle.plate } end
  ServerNotify(src, Config.Job.label, Locale('lobby_created', c.name), 'success')
  TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', src, buildLobbyInfo(c.name, lobbies[c.name]))
  TriggerClientEvent('dps-roxwoodracing:setLobbyState', -1, next(lobbies) ~= nil)
end)
```
3. `joinLobby(lobbyName)` → `joinLobby(lobbyName, vehicle)`; after the refund-cooldown check and before `ChargeEntryFee`, add:
```lua
    if lobby.mode == 'open' then
      if type(vehicle) ~= 'table' or not vehicle.plate then ServerNotify(src, Config.Job.label, Locale('open_need_vehicle'), 'error') return end
      if not Lobbies.VerifyOwnedVehicle(src, vehicle.plate) then ServerNotify(src, Config.Job.label, Locale('open_not_owner'), 'error') return end
      if not Lobbies.OpenClassAllows(lobby.class, tonumber(vehicle.class)) then ServerNotify(src, Config.Job.label, Locale('open_wrong_class', Config.OpenClasses[lobby.class].label), 'error') return end
      lobby.vehicles[src] = { netId = tonumber(vehicle.netId), plate = vehicle.plate }
    end
```
4. `buildLobbyInfo` adds `mode = lob.mode, class = lob.class, tune = lob.tune`.
5. `startRace`: after `pendingChoices[lobbyName] = ...` branch on mode. For **open** lobbies skip the vehicle-select flow entirely:
```lua
  if lob.mode == 'open' then
    for _, pid in ipairs(lob.players) do TriggerClientEvent('dps-roxwoodracing:hideLobbyWindow', pid) end
    StartOpenRace(lobbyName, lob)
    return
  end
```
   and add, next to `SpawnRaceVehicles`:
```lua
local function StartOpenRace(lobbyName, lob)
  while gridLocked do Wait(250) end
  gridLocked = true
  lob.gridOrder = {}
  local netIds = {}
  for idx, pid in ipairs(lob.players) do
    lob.gridOrder[pid] = idx
    local v = lob.vehicles[pid]
    local sp = Config.GridSpawnPoints[idx]
    if v and sp then
      TriggerClientEvent('dps-roxwoodracing:prepareStart', pid, {
        track = lob.track, laps = lob.laps, netId = v.netId, plate = v.plate, mode = 'open', tune = 'Stock', keepVehicle = true, grid = sp,
      })
      netIds[#netIds+1] = { pid = pid, netId = v.netId }
    end
  end
  TriggerClientEvent('dps-roxwoodracing:raceVehicles', -1, netIds)
  if Config.Ghosting.enabled and Config.Ghosting.startGhosted then
    lob.ghostActive = true
    CreateThread(function()
      Wait(Config.Ghosting.unghostTimerSeconds * 1000)
      if lob.ghostActive then lob.ghostActive = false; for _, pid in ipairs(lob.players) do TriggerClientEvent('dps-roxwoodracing:client:unghost', pid) end end
    end)
  end
  CreateThread(function() Wait(8000); gridLocked = false end)
end
```
6. `SpawnRaceVehicles`: plate line becomes `local plate = Plates.FromName(Bridge.GetPlayerFirstLast(pid))` — more exactly:
```lua
      local first, last = Bridge.GetPlayerFirstLast(pid)
      local plate = Plates.FromName(first, last, GetPlayerName(pid), usedPlates)
```
   `giveKeys` event passes `netId, plate`; `prepareStart` payload adds `mode = 'spec', tune = lob.tune, keepVehicle = false`.
7. `selectedVehicle`: replace the `VALID_MODELS` / `Config.RaceClasses` checks with `if not Lobbies.IsModelAllowed(lob.class, model) then return end`. `chooseVehicle` event passes `lob.class` (was `lob.raceClass`).
8. `lapPassed` finish: `TriggerClientEvent("dps-roxwoodracing:client:finishTeleport", src, Config.outCoords)` → `..., Config.outCoords, lob.mode == 'open')`.
9. Remove the two `TriggerClientEvent('dps-roxwoodracing:cam:broadcastOn'/'Off')` and `TriggerEvent('dps-roxwoodracing:feed:setLeader', ...)` lines (dead hooks for a feed module that does not exist).
10. `exports['dps-roxwoodracing']:ShowIdleLeaderboard()` calls stay (Task 14 keeps the export).

- [ ] **Step 5: Run tests, commit**

`./tools/check.sh` → `34 passed, 0 failed`.
```bash
git add server tests/test_lobbies.lua
git commit -m "Lobbies: registry-built spec catalogue, Open mode ownership checks, tune in the start payload"
```

---

### Task 11: Staff controls and boss menu

**Files:**
- Create: `server/staff.lua`, `integrations/bossmenu.lua` (one file, both sides guarded by `IsDuplicityVersion()`)
- Modify: `server/race.lua` (delete `/lb` command; expose `Race.EndLobby(name, reason)` and `Race.SetSignMode(name, mode)`), `client/main.lua` (add `/raceway` context menu), `locales/en.lua` (keys already added in Task 2)
- Test: `tests/test_staff.lua`

**Interfaces:**
- Produces (server): `Race.EndLobby(lobbyName, reason)` (refunds if not started, tears down props/zones for members, clears lobby, promotes the sign owner), `Race.SetSignMode(lobbyName, 'names'|'toggle')`, `Race.ListLobbies() → { {name, track, mode, started, players}, ... }`; `Staff.Can(src, gradeKey) → bool`; net event `dps-roxwoodracing:staff:action(action, payload)`; settings overrides persisted in table `dps_roxwoodracing_settings (k VARCHAR(40) PK, v VARCHAR(200))` and applied onto `Config.Economy` at boot (`Staff.LoadSettings`, `Staff.SetSetting(k, v)`).
- Produces (client): `BossMenu.AddItem()` registers "Raceway Control" in the qbx_management boss menu; `/raceway` opens the same ox_lib context for Marshal and above.

- [ ] **Step 1: Write the test**

`tests/test_staff.lua`:
```lua
TEST('Staff.Can checks job and grade through the bridge', function()
  RESET_STUB(); Config = { Job = { name = 'roxwoodracing', grades = { marshal = 0, director = 2, owner = 3 } }, Economy = { payouts = {}, entryFee = {} } }
  Bridge = { HasJob = function(src, job, g) return src == 1 and job == 'roxwoodracing' and g <= 2 end }
  Race = {}; dofile('server/staff.lua')
  TRUTHY(Staff.Can(1, 'marshal')); TRUTHY(Staff.Can(1, 'director')); FALSY(Staff.Can(1, 'owner')); FALSY(Staff.Can(2, 'marshal'))
end)

TEST('SetSetting validates keys and applies onto Config.Economy', function()
  RESET_STUB(); Config = { Job = { name = 'roxwoodracing', grades = {} }, Economy = { payouts = { [1] = 5000 }, entryFee = { amount = 1000 }, participationReward = 500, bestLapBonus = 1000 } }
  Bridge = {}; Race = {}; dofile('server/staff.lua')
  TRUTHY(Staff.SetSetting('payout1', 7000)); EQ(Config.Economy.payouts[1], 7000)
  TRUTHY(Staff.SetSetting('entryfee', 250)); EQ(Config.Economy.entryFee.amount, 250)
  FALSY(Staff.SetSetting('hack', 1)); FALSY(Staff.SetSetting('payout1', -5))
  TRUTHY(STUB.queries[#STUB.queries].sql:find('dps_roxwoodracing_settings'))
end)
```

- [ ] **Step 2: Run to see it fail** — FAIL.

- [ ] **Step 3: Write server/staff.lua**

```lua
Staff = {}
local SETTINGS = 'dps_roxwoodracing_settings'
local keys = {
  payout1 = function(v) Config.Economy.payouts[1] = v end,
  payout2 = function(v) Config.Economy.payouts[2] = v end,
  payout3 = function(v) Config.Economy.payouts[3] = v end,
  showup  = function(v) Config.Economy.participationReward = v end,
  bestlap = function(v) Config.Economy.bestLapBonus = v end,
  entryfee = function(v) Config.Economy.entryFee.amount = v; Config.Economy.entryFee.enabled = v > 0 end,
}

function Staff.Can(src, gradeKey)
  local g = Config.Job.grades[gradeKey] or 0
  return Bridge.HasJob and Bridge.HasJob(src, Config.Job.name, g) or false
end

function Staff.SetSetting(k, v)
  v = tonumber(v)
  if not keys[k] or not v or v < 0 or v ~= math.floor(v) then return false end
  keys[k](v)
  MySQL.query.await(('INSERT INTO %s (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = ?'):format(SETTINGS), { k, tostring(v), tostring(v) })
  return true
end

function Staff.LoadSettings()
  MySQL.query.await(('CREATE TABLE IF NOT EXISTS %s (k VARCHAR(40) NOT NULL PRIMARY KEY, v VARCHAR(200))'):format(SETTINGS))
  local rows = MySQL.query.await(('SELECT k, v FROM %s'):format(SETTINGS)) or {}
  for _, r in ipairs(rows) do if keys[r.k] and tonumber(r.v) then keys[r.k](tonumber(r.v)) end end
  print(('[dps-roxwoodracing] staff settings loaded: %d overrides'):format(#rows))
end

function Staff.Snapshot()
  local e = Config.Economy
  return { payout1 = e.payouts[1], payout2 = e.payouts[2], payout3 = e.payouts[3], showup = e.participationReward,
           bestlap = e.bestLapBonus, entryfee = e.entryFee.amount, purseSource = e.purseSource,
           balance = Banking and Banking.GetBalance(Config.Job.name) or 0, lobbies = Race.ListLobbies and Race.ListLobbies() or {} }
end

lib.callback.register('dps-roxwoodracing:staff:snapshot', function(src)
  if not Staff.Can(src, 'marshal') then return nil end
  return Staff.Snapshot()
end)

RegisterNetEvent('dps-roxwoodracing:staff:action', function(action, payload)
  local src = source
  payload = type(payload) == 'table' and payload or {}
  local function deny() TriggerClientEvent('dps-roxwoodracing:client:notify', src, Config.Job.label, Locale('staff_only'), 'error') end
  if action == 'endRace' then
    if not Staff.Can(src, 'marshal') then return deny() end
    Race.EndLobby(payload.lobby, 'staff')
  elseif action == 'clearProps' then
    if not Staff.Can(src, 'marshal') then return deny() end
    TriggerClientEvent('dps-roxwoodracing:client:destroyprops', -1)
  elseif action == 'signMode' then
    if not Staff.Can(src, 'marshal') then return deny() end
    Race.SetSignMode(payload.lobby, payload.mode)
  elseif action == 'setSetting' then
    if not Staff.Can(src, 'director') then return deny() end
    if not Staff.SetSetting(payload.key, payload.value) then
      TriggerClientEvent('dps-roxwoodracing:client:notify', src, Config.Job.label, 'Invalid value.', 'error')
    end
  end
end)

CreateThread(function() Wait(1500); Staff.LoadSettings() end)
```
Add to `tests/stubs.lua`: `function IsDuplicityVersion() return true end`.

- [ ] **Step 4: Add Race.EndLobby / SetSignMode / ListLobbies to server/race.lua**

Replace the `/lb` `RegisterCommand` block (old 398–435) with:
```lua
Race = Race or {}

function Race.ListLobbies()
  local out = {}
  for name, lob in pairs(lobbies) do out[#out+1] = { name = name, track = lob.track, mode = lob.mode, started = lob.isStarted, players = #lob.players } end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Race.SetSignMode(lobbyName, mode)
  if mode ~= 'names' and mode ~= 'toggle' then return end
  lobbyName = lobbyName or primaryLobby
  if not lobbyName or not lobbies[lobbyName] then return end
  amirState[lobbyName] = amirState[lobbyName] or { last = 0, lastSwitch = 0, showNames = true }
  amirState[lobbyName].vm = mode; amirState[lobbyName].last = 0; amirState[lobbyName].lastSwitch = 0; amirState[lobbyName].showNames = true
end

function Race.EndLobby(lobbyName, reason)
  local lob = lobbies[lobbyName]
  if not lob then return end
  for _, pid in ipairs(lob.players) do
    if not lob.isStarted then Rewards.RefundEntryFee(pid, lobbyName) end
    TriggerClientEvent('dps-roxwoodracing:kickedFromLobby', pid, lobbyName, reason or 'ended')
    TriggerClientEvent('dps-roxwoodracing:client:destroyprops', pid)
    TriggerClientEvent('dps-roxwoodracing:updateLobbyInfo', pid, nil)
    if lob.isStarted then TriggerClientEvent('dps-roxwoodracing:client:finishTeleport', pid, Config.outCoords, lob.mode == 'open') end
  end
  pendingChoices[lobbyName] = nil
  amirState[lobbyName] = nil
  lobbies[lobbyName] = nil
  TriggerClientEvent('dps-roxwoodracing:setLobbyState', -1, next(lobbies) ~= nil)
  if primaryLobby == lobbyName then
    primaryLobby = nil
    for n, l in pairs(lobbies) do if l.isStarted then primaryLobby = n break end end
    if Config.Leaderboard and Config.Leaderboard.enabled and not primaryLobby then exports['dps-roxwoodracing']:ShowIdleLeaderboard() end
  end
end
```
`lobbies`, `pendingChoices`, `amirState`, `primaryLobby` are declared above this point in the file (old line 298+); move the `Race` block below those declarations.

- [ ] **Step 5: Write integrations/bossmenu.lua**

```lua
-- Boss menu: qbx_management (native) or qb-bossmenu through the qbx bridge.
BossMenu = {}
if IsDuplicityVersion() then
  BossMenu.Provider = (GetResourceState('qbx_management') == 'started' or GetResourceState('qbx_management') == 'starting') and 'qbx_management'
    or (GetResourceState('qb-bossmenu') == 'started' and 'qb-bossmenu') or 'none'
  print(('[dps-roxwoodracing] bossmenu: %s'):format(BossMenu.Provider))
  function BossMenu.Register()
    if BossMenu.Provider == 'qbx_management' then
      pcall(function()
        exports.qbx_management:RegisterBossMenu({ groupName = Config.Job.name, type = 'job', coords = Config.Job.bossCoords, size = vec3(2.0, 2.0, 2.5) })
      end)
    end
  end
  CreateThread(function() Wait(2000); BossMenu.Register() end)
else
  BossMenu.Provider = (GetResourceState('qbx_management') == 'started' or GetResourceState('qbx_management') == 'starting') and 'qbx_management' or 'none'
  function BossMenu.AddItem()
    if BossMenu.Provider ~= 'qbx_management' then return end
    pcall(function()
      exports.qbx_management:AddBossMenuItem({
        title = Locale('raceway_control'),
        description = 'Fees, purse, sign, end race',
        icon = 'flag-checkered',
        event = 'dps-roxwoodracing:client:openControl',
        args = { type = 'job', groupName = Config.Job.name },
      })
    end)
  end
  CreateThread(function() Wait(2000); BossMenu.AddItem() end)
end
```
Note: `AddBossMenuItem` is queued into every boss menu; qbx_management filters by `args.groupName` when rendering. If it does not (verify on the box: `grep -n groupName qbx_management/client/main.lua`), gate the event handler with `Bridge.HasJob(Config.Job.name, 0)` — it is gated anyway below.

- [ ] **Step 6: Client control menu in client/main.lua**

Append:
```lua
local function openControl()
  if not Bridge.HasJob(Config.Job.name, Config.Job.grades.marshal) then Notify(Config.Job.label, Locale('staff_only'), 'error') return end
  local snap = lib.callback.await('dps-roxwoodracing:staff:snapshot', false)
  if not snap then return end
  local options = {}
  for _, l in ipairs(snap.lobbies) do
    options[#options+1] = { title = ('%s  %s  %s  %d racers'):format(l.name, l.track, l.mode, l.players), description = l.started and 'Running' or 'Waiting',
      menu = nil, onSelect = function()
        local pick = lib.inputDialog(l.name, { { type = 'select', label = 'Action', options = { { value = 'endRace', label = 'End race' }, { value = 'names', label = 'Sign: names' }, { value = 'toggle', label = 'Sign: names + times' } } } })
        if not pick then return end
        if pick[1] == 'endRace' then TriggerServerEvent('dps-roxwoodracing:staff:action', 'endRace', { lobby = l.name })
        else TriggerServerEvent('dps-roxwoodracing:staff:action', 'signMode', { lobby = l.name, mode = pick[1] }) end
      end }
  end
  options[#options+1] = { title = 'Clear track props', icon = 'broom', onSelect = function() TriggerServerEvent('dps-roxwoodracing:staff:action', 'clearProps') end }
  if Bridge.HasJob(Config.Job.name, Config.Job.grades.director) then
    options[#options+1] = { title = ('Account balance: $%s'):format(snap.balance), description = ('Purse source: %s'):format(snap.purseSource), disabled = true }
    local fields = { { 'entryfee', 'Entry fee' }, { 'payout1', '1st place' }, { 'payout2', '2nd place' }, { 'payout3', '3rd place' }, { 'showup', 'Show-up bonus' }, { 'bestlap', 'Fastest lap bonus' } }
    for _, f in ipairs(fields) do
      options[#options+1] = { title = ('%s: $%s'):format(f[2], snap[f[1]]), onSelect = function()
        local v = lib.inputDialog(f[2], { { type = 'number', label = 'Amount', default = snap[f[1]], min = 0 } })
        if v and v[1] then TriggerServerEvent('dps-roxwoodracing:staff:action', 'setSetting', { key = f[1], value = v[1] }) end
      end }
    end
  end
  lib.registerContext({ id = 'dps_roxwoodracing_control', title = Locale('raceway_control'), options = options })
  lib.showContext('dps_roxwoodracing_control')
end
RegisterNetEvent('dps-roxwoodracing:client:openControl', openControl)
RegisterCommand('raceway', openControl, false)
```
Delete the old `speedway_cleanup` command (renamed already to `dps-roxwoodracing_cleanup` by sed; remove it) — `clearProps` replaces it.

- [ ] **Step 7: Run tests, commit**

`./tools/check.sh` → `36 passed, 0 failed`.
```bash
git add server/staff.lua server/race.lua integrations/bossmenu.lua client/main.lua tests/test_staff.lua
git commit -m "Staff: job-gated raceway controls, boss menu item, persisted fee/purse settings"
```

---

### Task 12: NUI HUD replaces the three draw loops; brand colours

**Files:**
- Create: `client/hud.lua`
- Modify: `html/index.html`, `client/main.lua`
- Test: manual (NUI) + syntax gate

**Interfaces:**
- Produces: `Hud.ShowRace(position, total, lap, laps)`, `Hud.UpdatePosition(position, total)`, `Hud.UpdateLap(lap, laps)`, `Hud.HideRace()`, `Hud.SelectCountdown(seconds|nil)`; NUI actions `hud`, `hudHide`, `selectCountdown`.

- [ ] **Step 1: Write client/hud.lua**

```lua
Hud = {}
local state = { position = 0, total = 0, lap = 1, laps = 1, visible = false }

local function push()
  SendNUIMessage({ action = 'hud', visible = state.visible, position = state.position, total = state.total, lap = state.lap, laps = state.laps })
end

function Hud.ShowRace(position, total, lap, laps)
  state.position, state.total, state.lap, state.laps, state.visible = position or 0, total or 0, lap or 1, laps or 1, true
  push()
end
function Hud.UpdatePosition(position, total)
  if state.position == position and state.total == total then return end
  state.position, state.total = position, total
  if state.visible then push() end
end
function Hud.UpdateLap(lap, laps)
  if state.lap == lap and state.laps == laps then return end
  state.lap, state.laps = lap, laps
  if state.visible then push() end
end
function Hud.HideRace()
  state.visible = false
  SendNUIMessage({ action = 'hudHide' })
end
function Hud.SelectCountdown(seconds)
  SendNUIMessage({ action = 'selectCountdown', seconds = seconds })
end
```

- [ ] **Step 2: Add HUD markup and handlers to html/index.html**

Inside `<body>` (before the results overlay) add:
```html
<div id="hud" class="hud" hidden>
  <div class="hud-pos"><span class="hud-label">POS</span><span id="hudPos">1</span><span class="hud-of">/<span id="hudTotal">1</span></span></div>
  <div class="hud-lap"><span class="hud-label">LAP</span><span id="hudLap">1</span><span class="hud-of">/<span id="hudLaps">1</span></span></div>
</div>
<div id="selectTimer" class="select-timer" hidden>Pick your car: <span id="selectSeconds">30</span>s</div>
```
In the `<style>` block add:
```css
.hud{position:fixed;left:50%;bottom:3vh;transform:translateX(-50%);display:flex;gap:18px;font-family:'Barlow Condensed',sans-serif;color:#f4f1ea;text-shadow:0 2px 6px rgba(0,0,0,.6)}
.hud>div{background:rgba(27,35,64,.78);border-left:4px solid #ff7a45;padding:6px 14px;min-width:96px}
.hud-label{font-size:12px;letter-spacing:.14em;color:#aeb6d2;display:block}
.hud-pos span:nth-child(2),.hud-lap span:nth-child(2){font-size:34px;font-weight:700;line-height:1}
.hud-of{font-size:18px;color:#aeb6d2;margin-left:2px}
.select-timer{position:fixed;top:10vh;left:50%;transform:translateX(-50%);background:rgba(27,35,64,.85);color:#ffcc80;border:2px solid #ff7a45;padding:8px 18px;font-family:'Barlow Condensed',sans-serif;font-size:22px}
```
In the `window.addEventListener('message', ...)` chain add:
```js
      } else if (data.action === 'hud') {
        const hud = document.getElementById('hud');
        document.getElementById('hudPos').textContent = data.position;
        document.getElementById('hudTotal').textContent = data.total;
        document.getElementById('hudLap').textContent = data.lap;
        document.getElementById('hudLaps').textContent = data.laps;
        hud.hidden = !data.visible;
      } else if (data.action === 'hudHide') {
        document.getElementById('hud').hidden = true;
      } else if (data.action === 'selectCountdown') {
        const el = document.getElementById('selectTimer');
        if (data.seconds === null || data.seconds === undefined || data.seconds <= 0) { el.hidden = true; }
        else { document.getElementById('selectSeconds').textContent = data.seconds; el.hidden = false; }
```
Brand: in the same `<style>` block, replace every existing accent hex (grep for `#e6b400`, `#ffd700`, `#f39c12`, or whatever the motorsport restyle used as its accent: run `grep -o '#[0-9a-fA-F]\{6\}' html/index.html | sort | uniq -c`) so that the single most-used non-neutral accent becomes `#ff7a45`, panel backgrounds use `#1f2840`, and body text `#f4f1ea`. Keep gold/silver/bronze podium colours.

- [ ] **Step 3: Remove the three draw loops from client/main.lua**

- Delete the lobby draw thread (old 93–116) and the variables `lobbyDisplayActive/lobbyDisplayName/lobbyDisplayMembers` uses that only feed it (keep `lobbyNuiVisible`).
- Delete the select-countdown draw thread (old 757–770). In `vehicleSelectCountdown` handler call `Hud.SelectCountdown(remaining)`; in the `prepareStart` pre-handler call `Hud.SelectCountdown(nil)`.
- Delete the position/lap draw thread (old 1199–1218). In `updateLap` call `Hud.UpdateLap(cur, tot)`; in `updatePosition` call `Hud.UpdatePosition(position, total)`; in `prepareStart` after `inRace = true` call `Hud.ShowRace(0, 0, 1, totalLaps)`; in `client:finishTeleport` and `client:destroyprops` call `Hud.HideRace()`.
- Delete `DrawText3D` from `client/util.lua`? No: `integrations/target.lua` fallback uses it. Keep it.

Verify: `grep -n "while true" client/*.lua` must show only the ghost thread's `while ghostActive and inRace` (not `while true`) — i.e. zero matches.

- [ ] **Step 4: Syntax gate, commit**

`./tools/check.sh` → `syntax ok`, `36 passed`.
```bash
git add client/hud.lua client/main.lua html/index.html
git commit -m "HUD: NUI position/lap/countdown replaces per-frame DrawText threads; brand accent"
```

---

### Task 13: Client race flow — Spec spawn with tune, Open join, ghost module, pit zones

**Files:**
- Create: `client/ghost.lua`
- Modify: `client/main.lua`, `client/customs.lua`, `client/pit.lua`
- Test: `tests/test_customs.lua` (tune application logic with stubbed natives) + syntax gate

**Interfaces:**
- `Customs.ApplyTune(veh, presetKey)` sets mods from `Tune.ModsFor`; `Customs.ApplyStyle(veh)` = old random cosmetics (spec only).
- `Ghost.Start(myVeh, netIds)`, `Ghost.Stop()`, `Ghost.SetRaceVehicles(list)` — the old per-frame loop stays because it only runs while ghosted **and** in a race, but it exits the moment either ends.
- `Pit.Arm(lobbyMode)` creates one `lib.zones.sphere` per pit box; `Pit.Disarm()` removes them; the pit-stop sequence is `RunPitStop(veh, idx)` (the old inline body).
- Client → server `createLobby` sends the table from Task 10; `joinLobby` sends `{ netId, plate, class }` when the lobby is Open.

- [ ] **Step 1: Write the test**

`tests/test_customs.lua`:
```lua
TEST('ApplyTune sets indexed mods, resolves max, toggles turbo', function()
  RESET_STUB()
  Config = { Tune = { Race = { mods = { [11] = 'max', [12] = 1 }, toggles = { [18] = true } }, Stock = { mods = {}, toggles = {} } } }
  dofile('shared/tune.lua')
  local set, toggled, kit = {}, {}, nil
  function SetVehicleModKit(v, k) kit = k end
  function GetNumVehicleMods(v, slot) return slot == 11 and 4 or 2 end
  function SetVehicleMod(v, slot, idx) set[slot] = idx end
  function ToggleVehicleMod(v, slot, on) toggled[slot] = on end
  function DoesEntityExist() return true end
  function GetHashKey() return 0 end; function math.randomseed() end
  Customs = nil; dofile('client/customs.lua')
  Customs.ApplyTune(1, 'Race')
  EQ(kit, 0); EQ(set[11], 3); EQ(set[12], 1); TRUTHY(toggled[18])
  set = {}; Customs.ApplyTune(1, 'Stock'); EQ(next(set), nil)
end)
```
`client/customs.lua` currently runs `math.randomseed(GetGameTimer())` at load and defines natives-using functions only — confirm with `luac -l` that nothing else executes at load; if `RegisterNetEvent` or `CreateThread` calls exist at top level, they are already stubbed.

- [ ] **Step 2: Run to see it fail** — FAIL (Customs nil).

- [ ] **Step 3: Rework client/customs.lua**

Wrap the existing functions in a `Customs` table: `Speedway_ApplyAll(veh)` → `Customs.ApplyStyle(veh)`; delete `applyPerformanceMax` (tune replaces it; the old code called it inside `applyStyle` — remove that call). Add:
```lua
function Customs.ApplyTune(veh, presetKey)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return end
  local t = Tune.ModsFor(presetKey, Config)
  SetVehicleModKit(veh, 0)
  for slot, idx in pairs(t.mods) do
    local count = GetNumVehicleMods(veh, slot) or 0
    if count > 0 then
      local i = idx == 'max' and (count - 1) or math.min(tonumber(idx) or -1, count - 1)
      SetVehicleMod(veh, slot, i, false)
    end
  end
  for slot, on in pairs(t.toggles) do ToggleVehicleMod(veh, slot, on) end
end
```

- [ ] **Step 4: Write client/ghost.lua**

Move `raceNetIds`, `ghostActive`, `myRaceVeh`, `StartGhostThread` and the three ghost net-event handlers (old client/main.lua 231–294) into `client/ghost.lua` as:
```lua
Ghost = { active = false, netIds = {}, myVeh = nil }
function Ghost.SetRaceVehicles(list) Ghost.netIds = list or {} end
function Ghost.Stop()
  Ghost.active = false
end
function Ghost.Start(myVeh)
  Ghost.myVeh = myVeh
  if Ghost.active then return end
  Ghost.active = true
  local ghostEntities = {}
  CreateThread(function()                       -- per-frame only while ghosted in a race
    while Ghost.active and IsRaceActive() do
      if Ghost.myVeh and DoesEntityExist(Ghost.myVeh) then
        for _, ent in ipairs(ghostEntities) do if DoesEntityExist(ent) then SetEntityNoCollisionEntity(Ghost.myVeh, ent, true) end end
      end
      Wait(0)
    end
  end)
  CreateThread(function()                       -- 200 ms resolver, same lifetime
    while Ghost.active and IsRaceActive() do
      local resolved = {}
      for _, v in ipairs(Ghost.netIds) do
        local other = NetworkGetEntityFromNetworkId(v.netId)
        if DoesEntityExist(other) and other ~= Ghost.myVeh then resolved[#resolved+1] = other; SetEntityAlpha(other, Config.Ghosting.ghostAlpha, false) end
      end
      ghostEntities = resolved
      Wait(200)
    end
    for _, v in ipairs(Ghost.netIds) do local o = NetworkGetEntityFromNetworkId(v.netId); if DoesEntityExist(o) then ResetEntityAlpha(o) end end
    Ghost.active = false
  end)
end
RegisterNetEvent('dps-roxwoodracing:raceVehicles', function(list) Ghost.SetRaceVehicles(list) end)
RegisterNetEvent('dps-roxwoodracing:client:unghost', function() Ghost.Stop() end)
RegisterNetEvent('dps-roxwoodracing:client:setGhosted', function(on) if on then Ghost.Start(Ghost.myVeh) else Ghost.Stop() end end)
```
`IsRaceActive()` is the renamed `IsSpeedwayRaceActive()` from client/main.lua (rename with sed in main.lua and pit.lua). In main.lua replace `StartGhostThread()` with `Ghost.Start(veh)`, `myRaceVeh = veh` with nothing (Ghost.Start stores it), and every `ghostActive = false` / `raceNetIds = {}` / `myRaceVeh = nil` with `Ghost.Stop()`.

- [ ] **Step 5: Client lobby creation and join with modes (client/main.lua)**

Replace the `dps-roxwoodracing:client:createLobby` handler body (old 645–690) with:
```lua
RegisterNetEvent('dps-roxwoodracing:client:createLobby', function()
  if hasLobby then Notify(Locale('lobby_exists'), '', 'error') return end
  local modePick = lib.inputDialog(Locale('create_lobby'), {
    { type = 'select', label = Locale('select_mode'), required = true, default = 'spec',
      options = { { value = 'spec', label = Locale('mode_spec') }, { value = 'open', label = Locale('mode_open') } } },
    { type = 'number', label = Locale('number_of_laps'), required = true, min = 1, max = 10, default = 3 },
    { type = 'select', label = Locale('select_track'), required = true, default = 'Short_Track',
      options = { { value = 'Short_Track', label = Locale('Short_Track') }, { value = 'Drift_Track', label = Locale('Drift_Track') },
                  { value = 'Speed_Track', label = Locale('Speed_Track') }, { value = 'Long_Track', label = Locale('Long_Track') } } },
  })
  if not modePick then return end
  local mode, laps, track = modePick[1], tonumber(modePick[2]) or 3, modePick[3]
  local args = { track = track, laps = laps, mode = mode }
  if mode == 'open' then
    local classes = lib.callback.await('dps-roxwoodracing:getOpenClasses', false)
    local pick = lib.inputDialog(Locale('mode_open'), { { type = 'select', label = Locale('select_open_class'), required = true, default = 'Any', options = classes } })
    if not pick then return end
    args.class = pick[1]
    args.vehicle = GetMyVehicleInfo()
    if not args.vehicle then Notify(Config.Job.label, Locale('open_need_vehicle'), 'error') return end
  else
    local cat = lib.callback.await('dps-roxwoodracing:getSpecCatalogue', false)
    local classOpts, tuneOpts = {}, {}
    for _, key in ipairs(cat.order) do classOpts[#classOpts+1] = { value = key, label = cat.classes[key].label } end
    for _, key in ipairs(Config.TuneOrder) do tuneOpts[#tuneOpts+1] = { value = key, label = Config.Tune[key].label } end
    local pick = lib.inputDialog(Locale('mode_spec'), {
      { type = 'select', label = Locale('select_class'), required = true, default = 'All', options = classOpts },
      { type = 'select', label = Locale('select_tune'), required = true, default = 'Stock', options = tuneOpts },
    })
    if not pick then return end
    args.class, args.tune = pick[1], pick[2]
  end
  local rawName = GetPlayerName(PlayerId()) or 'Racer'
  local safeName = rawName:gsub('[^%w_]', '_'):sub(1, 30)
  if safeName == '' then safeName = 'Racer' end
  args.name = safeName .. '_' .. math.random(1000, 9999)
  TriggerServerEvent('dps-roxwoodracing:createLobby', args)
end)

function GetMyVehicleInfo()
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
  return { netId = NetworkGetNetworkIdFromEntity(veh), plate = GetVehicleNumberPlateText(veh), class = GetVehicleClass(veh) }
end
```
`joinLobby` handler: the `getLobbies` callback result already carries a label; add `mode` to each entry server-side (`mode = lobby.mode` in the `getLobbies` callback). After the dialog:
```lua
    local chosen = dialog[1]
    local vehicle = nil
    for _, e in ipairs(lobbies) do if e.value == chosen and e.mode == 'open' then vehicle = GetMyVehicleInfo() end end
    TriggerServerEvent('dps-roxwoodracing:joinLobby', chosen, vehicle)
```

- [ ] **Step 6: prepareStart per mode (client/main.lua)**

In the `prepareStart` handler:
- After `myRaceVeh = veh` / entity wait: branch.
```lua
    if data.mode == 'open' then
      -- Own car: no keys, no fuel, no style. Snap onto the grid slot and freeze for the countdown.
      SetEntityAsMissionEntity(veh, true, true)
      if data.grid then SetEntityCoords(veh, data.grid.x, data.grid.y, data.grid.z, false, false, false, true); SetEntityHeading(veh, data.grid.w); SetVehicleOnGroundProperly(veh) end
      FreezeEntityPosition(veh, true)
      SetVehicleUndriveable(veh, true)
    else
      SetEntityAsMissionEntity(veh, true, true)
      FreezeEntityPosition(veh, true)
      Keys.Give(veh, data.plate)
      Fuel.SetFull(veh)
      Customs.ApplyStyle(veh)
      Customs.ApplyTune(veh, data.tune or 'Stock')
      SetVehicleEngineOn(veh, true, true, false)
      SetVehicleUndriveable(veh, true)
      TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
      repeat Wait(0) until IsPedInAnyVehicle(PlayerPedId(), false)
      -- plate / fuel / unlock reassert windows: keep old code here unchanged
    end
```
  The old plate/fuel/unlock reassert threads and the countdown stay as they are (they end on their own timers).
- `finishTeleport(coords, keepVehicle)`: when `keepVehicle` is true do **not** `TaskLeaveVehicle`/`DeleteVehicle`; instead `FreezeEntityPosition(v, false)` and teleport the vehicle with the player to `coords` (`SetEntityCoords(v, ...)` then `SetVehicleOnGroundProperly(v)`).
- Store `raceMode = data.mode` in a client local; `Hud.ShowRace(0, 0, 1, data.laps)` after `inRace = true`.

- [ ] **Step 7: Pit zones (client/pit.lua)**

- Keep the crew spawn thread (old 14–99) and the `onClientResourceStop` cleanup.
- Cut the pit-stop body (old 158–531, the `if not inPit then ... if dist < radius and speed < 0.5 ...` inner block, from `inPit = true` to the `EndTextCommandPrint(3000, true)` line) into `local function RunPitStop(veh, idx)`; it ends with `inPit = false` after the crew returns is **not** how the old code worked (old code cleared `inPit` on zone exit) — keep that: `RunPitStop` returns after the crew is home; zone `onExit` unfreezes and clears `inPit` and sets the cooldown.
- Replace the `while true` detection thread (old 132–545) with:
```lua
Pit = { zones = {}, armed = false }
local inPit, pitCooldownUntil, waiting = false, 0, nil

local function watchForStop(idx)
  -- Runs only while the racer is inside pit box idx and not yet stopped.
  if waiting then return end
  waiting = idx
  CreateThread(function()
    while waiting == idx and IsRaceActive() do
      local veh = GetVehiclePedIsIn(PlayerPedId(), false)
      if veh ~= 0 and not inPit and GetEntitySpeed(veh) < 0.5 and GetGameTimer() > pitCooldownUntil then
        inPit = true
        RunPitStop(veh, idx)
        break
      end
      Wait(250)
    end
    if waiting == idx then waiting = nil end
  end)
end

function Pit.Arm()
  if Pit.armed then return end
  Pit.armed = true
  for idx, zone in ipairs(Config.PitCrewZones) do
    Pit.zones[idx] = lib.zones.sphere({
      coords = zone.coords, radius = zone.radius, debug = Config.ZoneDebug,
      onEnter = function() if IsRaceActive() then watchForStop(idx) end end,
      onExit = function()
        if waiting == idx then waiting = nil end
        if inPit then
          local veh = GetVehiclePedIsIn(PlayerPedId(), false)
          if veh ~= 0 then FreezeEntityPosition(veh, false) end
          inPit = false
          pitCooldownUntil = GetGameTimer() + 10000
        end
      end,
    })
  end
  -- Markers: a point per box; the nearby callback is per-frame only within 60 m.
  for idx, zone in ipairs(Config.PitCrewZones) do
    Pit.zones['pt' .. idx] = lib.points.new({ coords = zone.coords, distance = 60.0, nearby = function()
      local size = (zone.radius * 2.0) / 6.0
      DrawMarker(36, zone.coords.x, zone.coords.y, zone.coords.z + 1.0, 0, 0, 0, 0, 0, 0, size, size, size, 255, 255, 255, 200, false, true, 2, false, nil, nil, false)
    end })
  end
end

function Pit.Disarm()
  for k, z in pairs(Pit.zones) do pcall(function() z:remove() end); Pit.zones[k] = nil end
  Pit.armed = false; waiting = nil; inPit = false
end
```
- In `client/main.lua`: call `Pit.Arm()` right after the checkpoint zones are created in `prepareStart`, and `Pit.Disarm()` inside the `destroyprops` handler.
- Delete the old marker thread (old 550–569).

- [ ] **Step 8: Gate check, tests, commit**

```bash
grep -rn "while true" client/ integrations/ ; echo "exit=$? (1 = none left)"
```
Expected: `exit=1`. `./tools/check.sh` → `37 passed, 0 failed`.
```bash
git add client shared tests/test_customs.lua
git commit -m "Client: spec spawn with tune presets, Open-mode join, ghost module, pit zones instead of scans"
```

---

### Task 14: Leaderboard — live-only tick, idle push on change, export names

**Files:**
- Modify: `server/leaderboard.lua`, `client/leaderboard.lua`

**Interfaces:**
- Exports `ShowIdleLeaderboard` / `StopIdleLeaderboard` unchanged (race.lua calls them).
- Idle board: fetch once, push names once and times once (no 2 s flip loop); re-push only when `Stats.Save` reports a new record (`AddEventHandler('dps-roxwoodracing:recordSet')`).

- [ ] **Step 1: Rewrite ShowIdleLeaderboard**

Replace the loop (old 140–178) with:
```lua
  CreateThread(function()
    Wait(2000)
    local data = GetTopBestTimes()
    if not data then showText('BEST', { 'R', 'O', 'X', 'W', 'O', 'O', 'D', '', '' }); idleRunning = false; return end
    showPlayerNames('BEST', data.names)
    idleRunning = false
  end)
```
and add:
```lua
AddEventHandler('dps-roxwoodracing:recordSet', function()
  if idleStopFlag == false and not idleRunning then ShowIdleLeaderboard() end
end)
```
In `server/stats.lua`, after the upsert, `if newRecord then TriggerEvent('dps-roxwoodracing:recordSet') end`. `StopIdleLeaderboard` keeps setting `idleStopFlag = true`; `ShowIdleLeaderboard` resets it to `false` first.

- [ ] **Step 2: Name resolution without the bridge helper**

In `GetTopBestTimes`, wherever it mapped citizenid → name via `Bridge.GetAllPlayersWithIdentifier()`, use a local cache: `names[cid] = names[cid] or Bridge.GetPlayerNameFromDB(cid) or cid:sub(1, 8)`.

- [ ] **Step 3: Client DUI path and cleanup**

`client/leaderboard.lua` already points at `nui://dps-roxwoodracing/html/led.html` (Task 1 sed). Confirm the `html/led.html` file references `LCDMB___.TTF` and `ads/` relatively (they moved together). `grep -n "leaderboard/" html/led.html` must print nothing.

- [ ] **Step 4: Gate, commit**

`./tools/check.sh` → syntax ok, 37 passed.
```bash
git add server/leaderboard.lua server/stats.lua client/leaderboard.lua html/led.html
git commit -m "Leaderboard: idle board pushed once and on new records; names via DB lookup"
```

---

### Task 15: README, CHANGELOG, install notes

**Files:**
- Modify: `README.md`, `CHANGELOG.md`
- Create: `docs/install.md`

- [ ] **Step 1: docs/install.md** (exact snippets the deploy task applies)

```markdown
# Install on Del Perro Sands

1. Resource lives at `resources/[dps]/dps-roxwoodracing`. `ensure [dps]` already covers it.
2. qbx_core `shared/jobs.lua` — add:

    ['roxwoodracing'] = {
        label = 'Roxwood Raceway',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Marshal', payment = 75 },
            [1] = { name = 'Pit Crew', payment = 90 },
            [2] = { name = 'Race Director', payment = 120 },
            [3] = { name = 'Owner', isboss = true, bankAuth = true, payment = 160 },
        },
    },

3. jg-advancedgarages `config/config.lua` → `Config.GarageLocations` — add:

    ["Roxwood Raceway"] = {
      coords = vector3(-2890.0, 8085.0, 44.5),
      spawn = { vector4(-2896.1, 8077.2, 44.5, 183.7) },
      distance = 15,
      type = "car",
      hideBlip = false,
      blip = { id = 357, color = 17, scale = 0.7 },
      hideMarkers = true,
      markers = { id = 21, size = { x = 0.3, y = 0.3, z = 0.3 }, color = { r = 255, g = 122, b = 69, a = 120 }, bobUpAndDown = 0, faceCamera = 0, rotate = 1, drawOnEnts = 0 },
    },

   (coords are the paddock next to the lobby ped; adjust in-game once.)
4. Full server reboot. Boot log must show one line each for framework, notify, target, keys, fuel, banking, garages, bossmenu, stats.
5. The society account `roxwoodracing` is created on first boot with $0. Deposit a float before the first race or set `Config.Economy.purseSource = 'house'`.
```

- [ ] **Step 2: README.md** — rewrite the top to say what the resource is now (DPS, job, society, Spec/Open, tune presets), replace the Configuration section with the five config files and the `Config.Economy` / `Config.Tune` / `Config.OpenClasses` blocks verbatim, update the commands table (`/racestats`, `/lobby`, `/raceway`), the file structure block, the database section (`dps_roxwoodracing_stats`, `dps_roxwoodracing_settings`), keep Credits (MaxSuperTech, glitchdetector, DrCannabis) and add DPS Development.

- [ ] **Step 3: CHANGELOG.md** — prepend:
```markdown
## v3.0.0 — 2026-09-05 — dps-roxwoodracing
- Renamed to dps-roxwoodracing; event prefix `dps-roxwoodracing:`.
- New job `roxwoodracing` (Marshal, Pit Crew, Race Director, Owner); entry fees, pool and purse flow through the Renewed-Banking society account; `purseSource = 'society' | 'house'`.
- Lobby modes: Spec (any registered car, grouped by class, Stock/Street/Race tune) and Open (bring a car you own, class-gated).
- Autosensed integrations: qbx_core, Renewed-Banking, qbx_management, jg-advancedgarages, wasabi_carlock, ox_fuel, ox_target, ox_lib.
- No scan loops: NUI HUD, lib.zones pit boxes, lib.points markers, idle leaderboard pushed on change.
- Staff: boss-menu "Raceway Control" and `/raceway`; fee/purse overrides persisted.
- Stats table renamed to `dps_roxwoodracing_stats` (auto-migrated) with spec/open win counters.
- Removed: de/es/fr/ru locales, ESX-only branches that cannot run here, dead camera/feed hooks.
```

- [ ] **Step 4: Commit and open the PR**

```bash
git add README.md CHANGELOG.md docs/install.md
git commit -m "Docs: README for dps-roxwoodracing 3.0, install notes, changelog"
T=$(ssh debian@10.10.10.10 'gh auth token')
git push "https://x-access-token:${T}@github.com/DaemonAlex/dps-roxwoodracing.git" port-to-dps
ssh debian@10.10.10.10 'gh pr create -R DaemonAlex/dps-roxwoodracing -B main -H port-to-dps -t "Port rox_speedway to dps-roxwoodracing 3.0" -F -' <<'EOF'
Ports rox_speedway v2.4.2 into the [dps] layout per docs/superpowers/specs/2026-09-05-roxwoodracing-design.md.

- roxwoodracing job + Renewed-Banking society money (fees, pool, purse)
- Spec lobbies (any registered car, tune presets) and Open lobbies (own car)
- autosensed integrations, no scan loops, NUI HUD, pit zones
- stats table migration, staff controls, boss menu item

Unit tests: tools/check.sh (lua5.4). Install notes: docs/install.md.
EOF
```
No attribution footer in the PR body (standing rule).

---

### Task 16: Deploy to VM 200 and produce the proof

Each step is one change, reported before the next (standing rule). All commands run on the fivem VM as `debian`.

- [ ] **Step 1: Bench the old resource, install the new one**

```bash
sudo mkdir -p /opt/fivem/backups/roxwoodracing-20260905
sudo mv "/opt/fivem/server-data/resources/[dps]/rox_speedway" /opt/fivem/backups/roxwoodracing-20260905/rox_speedway
T=$(gh auth token)
sudo git clone -b port-to-dps "https://x-access-token:${T}@github.com/DaemonAlex/dps-roxwoodracing.git" "/opt/fivem/server-data/resources/[dps]/dps-roxwoodracing"
sudo git -C "/opt/fivem/server-data/resources/[dps]/dps-roxwoodracing" remote set-url origin https://github.com/DaemonAlex/dps-roxwoodracing.git
sudo chown -R fivem:fivem "/opt/fivem/server-data/resources/[dps]/dps-roxwoodracing"
```
Report: old path → backup path, new path, branch, commit hash.

- [ ] **Step 2: jobs.lua** — insert the block from `docs/install.md` §2 after the last job entry in `resources/[core]/[qbx]/qbx_core/shared/jobs.lua` (`.bak-roxwoodracing` copy first; `luac5.4 -p` the file after). Report the diff.

- [ ] **Step 3: jg garage** — insert the block from `docs/install.md` §3 into `Config.GarageLocations` in `resources/[rp]/[world]/[jg-suite]/[jg]/jg-advancedgarages/config/config.lua` (`.bak-roxwoodracing` first; `luac5.4 -p` after). Report the diff.

- [ ] **Step 4: Reboot** — `fx restart` (whole server, announce it), then wait for `fx status` to report `port : 30120 listening`.

- [ ] **Step 5: Proof (server side, quoted in the report)**

```bash
fx bootlog | grep -n "dps-roxwoodracing" | head -40          # expect: framework qbx, notify ox_lib, target ox_target, keys wasabi_carlock, fuel ox_fuel, banking Renewed-Banking, garages jg-advancedgarages, bossmenu qbx_management, stats table ready, staff settings loaded, Started resource
fx bootlog | grep -n -i "error\|warn" | grep -i roxwood       # expect: nothing
mysql -e "SHOW TABLES LIKE 'dps_roxwoodracing%'; SELECT COUNT(*) FROM dps_roxwoodracing_stats; SHOW TABLES LIKE 'speedway_stats';"   # expect: 2 tables, old row count preserved, old table gone
mysql -e "SELECT id, amount FROM bank_accounts_new WHERE id='roxwoodracing';"   # expect: one row, amount 0
```
(mysql creds: `/root/qbox-credentials` on hv → LXC 201.)

- [ ] **Step 6: In-game checks (Stor)** — from the spec §8: ped/grid/pit/LED placement on the fresh Roxwood, one Spec race and one Open race with two players. After the first race with a fee: `mysql -e "SELECT title, amount, trans_type FROM bank_transactions WHERE account='roxwoodracing' ORDER BY id DESC LIMIT 10"` — quote it.

- [ ] **Step 7: Report** — one artifact section: what moved where, the two config diffs, the boot-log lines, the DB rows, what is still open (in-game checks).

---

## Self-review

**Spec coverage**
- §1 Shape → Tasks 1, 2. Event prefix → Task 1 step 2.
- §2 Business: job grades → install.md (Task 15) + jobs.lua (Task 16 step 2); society account creation → Task 7 (`Banking.EnsureAccount` at boot); fee/pool/purse/house toggle → Tasks 5–7; prize car with `garage_id` → Task 5; garage entry → Task 16 step 3.
- §3 Cars: Spec catalogue from registry + presets + tune → Tasks 10, 13; Open ownership + class gate + keep vehicle → Tasks 10, 13.
- §4 Wiring table → Tasks 3, 4, 5, 11 (bossmenu).
- §5 No scanners: HUD → Task 12; pit zones/points → Task 13; leaderboard idle push → Task 14; ghost loop bounded → Task 13.
- §6 Staff and data: boss menu item, `/raceway`, settings → Task 11; stats rename/migration/mode counters → Task 8.
- §7 Untouched: tracks/props/checkpoints untouched (Task 2 moves them verbatim); ghost rules, results overlay, pit animations kept (Task 13 moves the body, does not edit it); locales dropped (Task 1).
- §8 Proof and delivery → Tasks 15, 16.

**Placeholder scan**: none of "TBD/TODO/handle edge cases/similar to Task N". Two spots deliberately reference the old file by line number ("move verbatim"); the executor has the file.

**Type consistency**: `Rewards.Settle(lob, results, bestLapPid)` returns `payouts, purseCovered` (Tasks 7, 9, 10 agree). `Validate.CreateArgs(args, cfg)` needs `cfg.SpecClassKeys`, populated by `Lobbies.SpecCatalogue()` at boot (Task 10) before any lobby can be created; the test in Task 6 supplies it directly. `prepareStart` payload fields `{track, laps, netId, plate, mode, tune, keepVehicle, grid}` match between Task 10 (server) and Task 13 (client). `finishTeleport(coords, keepVehicle)` matches Tasks 10, 11, 13. `Keys.Give(veh, plate)` matches Tasks 4, 13; the `client:giveKeys` event carries `netId, plate` in both.
