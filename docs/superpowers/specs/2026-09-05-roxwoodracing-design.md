# dps-roxwoodracing — design spec

Date: 2026-09-05 · Status: approved by Stor (artifact rev 1) · Source: rox_speedway v2.4.2 @ e6e21ff

## Verdict

Port, don't rewrite. The proven lap, ranking and ghosting code from rox_speedway moves
into a [dps]-shaped resource with a real job, a society account, autosense bridges for
every vendor on the DPS box, and no scan loops. Two lobby modes: **Spec** (track cars,
any model, lobby-wide tune) and **Open** (bring your own car).

## Decisions already made

- Cars: both modes, chosen per lobby by the host.
- Ownership: a business with a job (`roxwoodracing`), not a city amenity.
- Scope: keep lobbies/laps/results/stats, pit crew NPCs, LED leaderboard sign,
  ghosting, entry fees and prize car.
- Approach: port file-by-file into the [dps] layout.
- Stor, mid-design: "gta5 has a lot of permutations of cars and we can use any car we
  want and tune them as needed" → spec fleet is any registered vehicle plus tune presets.

## 1. Shape

Resource name `dps-roxwoodracing`, laid out like dps-parking / dps-towjob:

```
dps-roxwoodracing/
  fxmanifest.lua
  bridge/            framework bridge, loaded first: qbx_core → qb-core → es_extended
    init.lua  client.lua  server.lua
  integrations/      one file per vendor, autosensed at boot
    banking.lua      Renewed-Banking society account
    bossmenu.lua     qbx_management
    garages.lua      jg-advancedgarages (prize car)
    keys.lua         wasabi_carlock
    fuel.lua         ox_fuel statebag
    notify.lua       ox_lib
    target.lua       ox_target
  config/
    config.lua       timing, keys, debug
    tracks.lua       checkpoints, segment hints, track props
    vehicles.lua     spec fleet presets, class filters, tune presets
    economy.lua      fees, purse, job name, grades used for gating
    pit.lua          pit boxes, crew models, timings
  client/
    main.lua         lobby + race orchestration
    hud.lua          NUI HUD (replaces the DrawText loops)
    ghost.lua
    pit.lua          lib.zones per pit box
    customs.lua      random style + plate
    leaderboard.lua  DUI sign
  server/
    lobbies.lua
    race.lua         ranking, laps, finish
    rewards.lua      fees, pool, purse, prize car
    stats.lua
    staff.lua        job-gated controls
    leaderboard.lua
  html/              lobby, HUD, results, LED renderer, LCD font, ad images
  stream/            LED sign ytyp/ydr/ytd/ymap
  locales/en.lua
  docs/superpowers/specs/
```

- Event and callback names change from `speedway:*` to `dps-roxwoodracing:*`.
  Verified 2026-09-05: nothing outside the resource references `speedway:`.
- Old code is kept where proven, moved where misplaced, replaced only where it scans.

## 2. The business

Job `roxwoodracing` in qbx_core `shared/jobs.lua` (one edit, reported):

| Grade | Name | Pay/10 min | Can |
|---|---|---|---|
| 0 | Marshal | 75 | clear track props, end a stuck race, switch LED sign mode |
| 1 | Pit Crew | 90 | Marshal + staffs pit boxes (NPC crew still works when nobody is on duty) |
| 2 | Race Director | 120 | + set fees, purse and laps for an event; kick a racer |
| 3 | Owner | 160 | boss menu, bank access (`isboss = true, bankAuth = true`), hire/fire |

Society account = job name, created at boot with `CreateJobAccount` if missing.

Money flows (all through Renewed-Banking, none minted silently):

- **Entry fee**: player cash → society account. Refunded from the account on cancel.
- **Buy-in pool**: sum of that race's fees, split 60/30/10 to the podium, paid from the
  account after the finish.
- **Podium purse**: 5000/3000/1500, best lap 1000, show-up 500, paid from the account.
  If the account cannot cover the purse, the race pays the pool only and the results
  screen says so. Staff top the account up at the bank / boss menu.
- **Prize car** (optional): `player_vehicles` row with `garage_id = 'Roxwood Raceway'`
  (jg-advancedgarages column), i.e. the paddock garage from section 8 step 4.
- `Economy.purseSource = 'society'` (default) | `'house'`. House mints the purse as
  today but logs every payment as a society transaction via `handleTransaction`.

## 3. Cars

Host picks the mode when creating the lobby. Grid, countdown, ghosting, laps and
results are identical in both.

| | Spec (track cars) | Open (bring your own) |
|---|---|---|
| Car | Spawned by the raceway. Random livery, plate from driver name (as today). | The car the driver sits in when joining. Server checks the plate belongs to their citizenid in `player_vehicles` before seating them. |
| Choice | Any vehicle the server knows: spec menu built from the vehicle registry at boot, grouped by game class. Old curated lists survive as optional named presets in `config/vehicles.lua`. | Host picks a game vehicle class (Super, Sports, Muscle, Off-road, Bikes, Any). Wrong class cannot join. |
| Tune | Host picks Stock / Street (engine 2, brakes 2, gearbox 2) / Race (max engine, brakes, gearbox, turbo on). Applied at spawn, same for every car in the lobby. | Untouched. |
| Keys, fuel | wasabi_carlock key, ox_fuel statebag full. | Untouched. |
| After | Car deleted, driver returned to paddock. | Car stays. |
| Pit crew | Works. | Works; repairs and fuel are real. |

Race-only cars reach Roxwood without the street via the paddock garage (section 8 step 4).

## 4. Wiring (compatibility contract)

Each integration file detects its vendor with `GetResourceState` at boot, prints one
line saying what it found, and exposes the same small function set. No other file
names a vendor.

| Need | On this box | Call | If missing |
|---|---|---|---|
| Society money | Renewed-Banking | `addAccountMoney`, `removeAccountMoney`, `getAccountMoney`, `CreateJobAccount`, `handleTransaction` | qb-banking → direct player cash + boot warning |
| Boss menu | qbx_management | `RegisterBossMenu`, `AddBossMenuItem` | `qb-bossmenu:client:OpenMenu` via qbx bridge |
| Prize car | jg-advancedgarages | `player_vehicles` + `garage_id` | plain row, garage `pillboxgarage` |
| Keys | wasabi_carlock | `exports.wasabi_carlock:GiveKey(plate)` (client) | qs-vehiclekeys → qb-vehiclekeys → unlock only |
| Fuel | ox_fuel | `Entity(veh).state.fuel = 100.0` | LegacyFuel / cdn-fuel exports |
| Target | ox_target | `addLocalEntity` on the lobby ped | qb-target |
| Notify | ox_lib | `lib.notify` | okokNotify |
| Framework | qbx_core | `exports.qbx_core:GetPlayer` etc. | qb-core → es_extended |

The bridge reports `qbx` (today's "qbcore" is the bridge shim working by accident).

## 5. No scanners

| Today | Replacement |
|---|---|
| Lobby panel DrawText every frame | NUI panel in the lobby page, updated on lobby events |
| Vehicle-select countdown DrawText every frame | same page, one timer element |
| Position/lap HUD DrawText every frame | NUI HUD, pushed only when position or lap changes |
| Pit detection polling the player's vehicle every 500 ms | `lib.zones.sphere` per pit box, created at GO, removed at finish; `onEnter` starts the stop |
| Pit markers drawn every frame during a race | `lib.points`, marker thread exists only near a box |

Leaderboard server tick keeps 1 s cadence but only while a race is live; the idle board
is pushed once when a record changes. In-game menus/NUI snap to the #ff7a45 brand ladder.

## 6. Staff and data

- Boss menu item **Raceway Control** (Owner): purse/fee settings, LED sign mode, end
  race, clear props, ledger link.
- `/raceway` (Marshal+): ox_lib context menu with end-race, clear-props, sign-mode.
  Job checked server-side.
- `/racestats` stays. `/speedway_cleanup` and `/lb` fold into the above.
- Table `dps_roxwoodracing_stats`: today's columns plus `spec_wins`, `open_wins`.
  On first boot, if `speedway_stats` exists and the new table does not, `RENAME TABLE`.
  Track keys (`Short_Track` …) unchanged so best laps still match.

## 7. Untouched

Four track layouts, checkpoints, segment hints (coordinates checked in-game once on the
reinstalled Roxwood pack); closest-point ranking, lap counting, photo-finish sort;
ghosting rules, results overlay and badges; pit crew animations/timings; LED sign model,
LCD font, DUI renderer, ad images; concurrent races on different tracks.

Dropped on purpose: de/es/fr/ru locales, qb-input remnants, ESX-only branches.

## 8. Proof and delivery

Server-side proof produced by Claude: boot log with one detection line per integration,
table ready, zero resource errors; stats table exists with old rows; society account
exists; a test fee shows in `getAccountTransactions`.

In-game checks by Stor: ped, grid, pit boxes and LED sign sit right on the fresh
Roxwood; one Spec race and one Open race, two players, three laps.

Delivery steps, each reported before the next:

1. Private repo `DaemonAlex/dps-roxwoodracing` carrying rox_speedway history; work on
   branch `port-to-dps`; PR for Stor's approval; no attribution footers.
2. Move `[dps]/rox_speedway` to backups (never deleted); clone the new resource in place.
3. Add job `roxwoodracing` to jobs.lua.
4. Add garage "Roxwood Raceway" at the paddock to jg-advancedgarages config.
5. Full server reboot, then the proof list.

Rollback = step 2 reversed + rename the stats table back.

## Parked

Hobbled used race cars / jg-mechanic upgrade ladder; DPS sponsor images for the LED
sign; sharing with qs-advancedracing or rcore_formula; a racing licence or tier gate
for Open lobbies.
