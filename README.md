# dps-roxwoodracing

Roxwood Raceway for Del Perro Sands. Lobby-based circuit racing with two modes, NPC pit crews, an in-world LED leaderboard, persistent career stats, staff controls, and a real business behind it: the `roxwoodracing` job, whose society account takes every entry fee and pays every purse.

Version 3.0.0. Descended from [max_rox_speedway](https://github.com/MaxSuperTech/max_rox_speedway) by MaxSuperTech, via rox_speedway (DrCannabis / DaemonAlex). Everything from v3.0 onward is the DPS port; the history is in `CHANGELOG.md`, the design in `docs/superpowers/specs/`, the build plan in `docs/superpowers/plans/`.

---

## Contents

1. [What it does](#what-it-does)
2. [How a race runs](#how-a-race-runs)
3. [Spec and Open modes](#spec-and-open-modes)
4. [Money](#money)
5. [The job and staff controls](#the-job-and-staff-controls)
6. [Requirements and what is detected](#requirements-and-what-is-detected)
7. [Install](#install)
8. [Configuration reference](#configuration-reference)
9. [Commands and keys](#commands-and-keys)
10. [Database](#database)
11. [Events, callbacks and exports](#events-callbacks-and-exports)
12. [Layout](#layout)
13. [Tests](#tests)
14. [Security model](#security-model)
15. [Troubleshooting](#troubleshooting)
16. [Credits and license](#credits-and-license)

---

## What it does

- **Lobbies.** Walk up to the paddock ped, create or join. The host starts the countdown. Four layouts (Short, Drift, Speed, Long) with checkpoint ranking that stays accurate through curves. Concurrent races on different layouts share one grid safely.
- **Spec mode.** The raceway spawns the cars. Any vehicle the server registers is on the menu, grouped by class, plus the base-game list and the curated presets. The host picks a lobby-wide tune: Stock, Street or Race. Cars are deleted after the race.
- **Open mode.** Bring a car you own. The server checks the car exists, the plate is yours, you are in the driver seat, and the car fits the class the host chose. You keep the car afterwards, damage and all.
- **Pit crews.** NPC crews refuel and repair when you stop inside a pit box. Fuel sync is server-authorised (your own race car, inside a pit box, or nothing happens).
- **Ghosting.** Everyone is ghosted at GO until all racers pass the first checkpoint (or a timer runs out). Racers a full lap behind the leader are ghosted so they cannot block.
- **Results.** A results overlay with positions, total and best lap times, payouts, gold/silver/bronze styling, "fastest lap" and "most improved" badges, and a note when the purse could not be paid.
- **Persistent stats.** Wins, podiums, races, earnings, spec and open wins, best lap per layout. `/racestats`.
- **Practice lines.** A Race Director records the racing line once with `/recordline <name>` (drive or walk one easy lap, run it again to save; points every 12 m, stored in `dps_roxwoodracing_lines`). Lines drive the AI practice cars.
- **AI practice cars.** When no race is live and a player is near the track, an open-wheel grid laps the recorded lines, each car on a random line with its own pace and lane bias, slowing behind and passing other racers. They are local to each client, so they cost the server nothing, and they vanish the moment a race goes live. `Config.Practice.ai` sets the count, models, speed, stagger and awareness.
- **LED sign.** A physical leaderboard at the raceway: live positions during a race, best-ever times when idle, refreshed when a record falls. The three ad panels show the DPS sponsor slides in `html/ads/` (`Config.Leaderboard.adUrls`); the texture replacement is re-applied whenever a player comes within `signRadius` of `signCoords`.
- **Staff.** Marshals end stuck races, clear props and switch the sign; Race Directors set fees and purse; the Owner has the boss menu and bank access.

## How a race runs

1. **Create.** Host picks mode, laps (1–10) and layout. Spec hosts then pick a class group and a tune; Open hosts pick an allowed vehicle class and must be sitting in a car they own.
2. **Join.** Others join from the same ped. Open joiners must also be in an owned car of the right class. Entry fee is charged at create/join and refunded on leave before the start (30 s rejoin cooldown to stop fee cycling). A lobby holds as many racers as there are grid slots.
3. **Start.** Only the host can start. Spec racers get a 30 s car picker; anyone who does not pick is dropped from the race. Open racers are snapped onto their grid slot in their own car.
4. **Countdown.** Cars are frozen, engines on. `Config.RaceStartDelay` seconds, then GO. Ghosting begins.
5. **Race.** Checkpoints must be crossed in order; the finish line counts a lap only after the last checkpoint. Position is lap, then checkpoint, then distance along the track (with segment hints for curves). Pit boxes are live.
6. **Finish.** Each finisher is teleported to the paddock (Spec: car deleted; Open: car comes with them). When the last racer finishes, or the last remaining racer disconnects, the race settles: payouts, stats, results overlay, sign back to idle.
7. **Disconnects and leavers.** A player who drops or leaves is removed from the lobby. Before the start their fee is refunded; mid-race their spec car is deleted, the host role passes on if needed, and the race ends when the others are done. An empty lobby closes itself.

## Spec and Open modes

| | Spec (track cars) | Open (bring your own) |
|---|---|---|
| Car | Spawned by the raceway on the grid, random livery, plate made from the driver's name | The car you are sitting in when you create or join |
| Choice | Any registered vehicle grouped by class, plus `Vanilla` (base game) and named presets | Host picks an allowed class: Any, Super, Sports, Muscle, Off-road, Motorcycles |
| Tune | Stock / Street / Race, the same for every car in the lobby | Untouched |
| Keys and fuel | Given and filled at spawn | Untouched |
| After the race | Car deleted | Car kept |
| Pit crew | Works | Works, and the repairs are real |

How a race-only car reaches Roxwood without touching the street: the paddock garage (a jg-advancedgarages location added at install). Pull it there, race it, park it there. That garage also receives prize cars.

**Tune presets** are mod indices applied with `SetVehicleMod`: Street = engine, brakes, gearbox level 2; Race = the highest available of each plus turbo. Change or add presets in `Config.Tune`; the menu order is `Config.TuneOrder`.

## Money

Everything goes through the society account named after the job (`roxwoodracing`) in Renewed-Banking, so the ledger is the single source of truth.

| Flow | Direction | Rule |
|---|---|---|
| Entry fee | player cash → account | Charged at create/join. Refunded from the account on leave/drop before the start. If the bank refuses the deposit the cash is handed straight back. |
| Buy-in pool | account → podium | The sum of that race's fees, split 60 / 30 / 10 to the top three. Always paid; it is the racers' own money. |
| Podium purse | account → racers | 5000 / 3000 / 1500 for the podium, 500 show-up for everyone, 1000 fastest lap. Paid only if the account can cover the whole purse **and** the race had at least `minPlayersForPurse` racers (default 2). Otherwise the race pays the pool only and the results screen says why. |
| Prize car | account → winner's garage | Optional (`vehiclePrize`). Written into `player_vehicles` at the paddock garage with a plate checked for uniqueness. |
| House mode | minted | `purseSource = 'house'` mints the purse instead of withdrawing it, but every payment is still written to the ledger. |

**The account starts at $0.** Deposit a float before the first race or set `purseSource = 'house'`.

## The job and staff controls

Grades in `qbx_core/shared/jobs.lua` (see Install):

| Grade | Name | Pay / 10 min | Can |
|---|---|---|---|
| 0 | Marshal | 75 | End a stuck race, clear track props, switch the LED sign mode |
| 1 | Pit Crew | 90 | Marshal powers (NPC crews still work with nobody on duty) |
| 2 | Race Director | 120 | + set entry fee, podium purse, show-up and fastest-lap bonuses |
| 3 | Owner | 160 | Boss menu, bank access (`isboss`, `bankAuth`), hires and fires |

**Raceway Control** opens from `/raceway` (Marshal and up) or from the qbx_management boss menu. It lists live lobbies (end race, sign mode), a "clear props" action that only reaches players not currently in a lobby, and for Directors the account balance plus the six money settings. Settings persist in `dps_roxwoodracing_settings`, override `Config.Economy` at boot, and are capped at `maxStaffSetting`.

## Requirements and what is detected

Hard requirements: **ox_lib**, **oxmysql**, and a framework (qbx_core first, then qb-core, then es_extended). Everything else is detected at boot with a fallback; one line per integration is printed at start.

| Need | Detected | Fallback |
|---|---|---|
| Society money | Renewed-Banking | qb-banking, then plain player cash (warning printed) |
| Boss menu | qbx_management | qb-bossmenu event through the qbx bridge |
| Prize car | jg-advancedgarages (`garage_id` column) | stock `garage` column |
| Keys | wasabi_carlock | qs-vehiclekeys, Renewed-Vehiclekeys, qb-vehiclekeys, unlock only |
| Fuel | ox_fuel statebag | LegacyFuel, cdn-fuel, okokGasStation, qs-fuelstations, natives |
| Target | ox_target | qb-target, proximity key |
| Notify | ox_lib | okokNotify, console |
| Vehicle registry | qbx_core / qb-core `GetVehiclesByName` | `Config.SpecFallbackVehicles` only |

## Install

1. Put the folder at `resources/[dps]/dps-roxwoodracing` (or anywhere `ensure`d after ox_lib, oxmysql, your framework and the vendors above).
2. Add the job. qbx_core `shared/jobs.lua`:

```lua
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
```

3. Add the paddock garage. jg-advancedgarages `config/config.lua`, inside `Config.GarageLocations` (mind the comma on the entry before it):

```lua
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
```

4. Restart the server. The boot log must show `framework`, `banking`, `garages`, `bossmenu`, `stats: table ready`, `spec catalogue`, `staff settings loaded` lines from `[dps-roxwoodracing]`. Client-side lines (`notify`, `target`, `keys`, `fuel`) appear in the player's F8 console.
5. Give someone the job (`/setjob <id> roxwoodracing 3`), open the boss menu, and deposit a float into the account.
6. Walk the paddock once: the lobby ped, grid slots, pit boxes, the LED sign and the garage marker are placed for the Roxwood County map as shipped; nudge `config/tracks.lua`, `config/pit.lua` and `Config.Job.bossCoords` if your build differs.

Migration from rox_speedway: the old `speedway_stats` table is renamed automatically on first boot; nothing is lost. Remove the old resource first, they cannot run side by side.

## Configuration reference

### `config/config.lua`

| Key | Default | Meaning |
|---|---|---|
| `Framework` | `nil` | Force `'qbx'`, `'qb'` or `'esx'`; nil auto-detects |
| `Locale` | `"en"` | Only `en` ships |
| `RaceStartDelay` | `10` | Countdown seconds |
| `ProgressTickMs` | `150` | How often a client reports its track distance (server accepts at most one per 100 ms and rebroadcasts the board at most every 200 ms per lobby) |
| `DistanceUseNoseCorners` | `true` | Use the front corners of the car for distance, so a nose decides a photo finish |
| `DebugPrints` / `ZoneDebug` | `false` | Console debug; draw ox_lib zones |
| `RankingInvert` | `false` | Flip displayed ranks if your layout is mirrored |
| `InteractKey` / `InteractKeyLabel` | `'F2'` | Lobby panel focus key and its label |
| `Leaderboard.enabled` | `true` | Drive the LED sign |
| `Leaderboard.idleDisplay` | `true` | Show best times when no race is running |
| `Leaderboard.updateIntervalMs` | `1000` | Minimum gap between live pushes |
| `Leaderboard.toggleIntervalMs` | `2000` | Names/times flip cadence in `toggle` mode |
| `Leaderboard.viewMode` | `"toggle"` | `toggle` or `names` |
| `Leaderboard.timeMode` | `"total"` | `total` race time or current `lap` time |
| `Ghosting.enabled` | `true` | Master switch |
| `Ghosting.startGhosted` | `true` | Ghost everyone at GO |
| `Ghosting.unghostOnCheckpoint` | `1` | Unghost when all racers pass this checkpoint (0 = timer only) |
| `Ghosting.unghostTimerSeconds` | `15` | Fallback timer |
| `Ghosting.lappedGhosting` | `true` | Ghost racers a lap behind the leader |
| `Ghosting.ghostAlpha` | `150` | Ghost transparency 0–255 |
| `ResultsUI.enabled` | `true` | Results overlay instead of toasts |
| `ResultsUI.displayDurationMs` | `20000` | Auto-dismiss |
| `ResultsUI.showBestLap` / `showMostImproved` | `true` | Badges |

### `config/tracks.lua`

`Checkpoints[layout]` (ordered vector3 list), `SegmentHints[layout]` (extra points between checkpoints for curved ranking), `StartLinePoints`, `FinishLine` (`coords`, `radius`), `GridSpawnPoints` (vector4 list; also the lobby size), `TrackProps[layout]` (tyre walls placed for the race), `outCoords` (paddock return point), `LobbyPed` (`model`, `coords`). Layout keys `Short_Track`, `Drift_Track`, `Speed_Track`, `Long_Track` are also the stats keys; renaming one orphans its best laps.

### `config/vehicles.lua`

| Key | Meaning |
|---|---|
| `SpecFallbackVehicles` | `{ label, model }` list of base-game cars. Merged into the catalogue as the `Vanilla` group (the addon registry never contains them). The whole menu if there is no registry. |
| `SpecPresets` | Named groups with a `vehicles` model list (Super, Tuner, Muscle, Bikes, Vans, Rally). Only models the catalogue knows are offered; empty presets are skipped with a boot note. |
| `OpenClasses` | `{ label, classes = { [GetVehicleClass id] = true } }`; `classes = nil` means any |
| `Tune` / `TuneOrder` | Presets: `mods = { [modType] = index or 'max' }`, `toggles = { [modType] = bool }` |
| `SpecClassLabels` | Class id → label used when grouping (informational) |

### `config/economy.lua`

| Key | Default | Meaning |
|---|---|---|
| `Job.name` / `Job.label` | `roxwoodracing` / `Roxwood Raceway` | Job and society account name |
| `Job.grades` | marshal 0, pitcrew 1, director 2, owner 3 | Grade thresholds the script checks |
| `Job.bossCoords` | paddock office | qbx_management boss zone |
| `Economy.purseSource` | `'society'` | `'society'` pays from the account; `'house'` mints but logs |
| `Economy.entryFee` | `{ enabled = true, amount = 1000 }` | Buy-in |
| `Economy.poolSplit` | `60 / 30 / 10` | Percent of the pool to positions 1–3 |
| `Economy.payouts` | `5000 / 3000 / 1500` | Podium purse |
| `Economy.participationReward` | `500` | Show-up bonus |
| `Economy.bestLapBonus` | `1000` | Fastest lap of the race |
| `Economy.vehiclePrize` | `nil` | Model name to award the winner, or nil |
| `Economy.prizeGarage` | `'Roxwood Raceway'` | jg garage id the prize car is parked in |
| `Economy.moneyType` | `'cash'` | Player side of every transaction |
| `Economy.minPlayersForPurse` | `2` | Fewer racers than this: pool only |
| `Economy.maxStaffSetting` | `1000000` | Ceiling for values set from Raceway Control |

### `config/pit.lua`

`PitCrewZones` (`coords`, `heading`, `radius` per box), `PitCrewModels` (random model + outfit per crew member; missing models are skipped), `PitCrewIdleOffsets`, `PitCrewCrewOffsets`, `PitStopTiming` (`crewWalkSpeed`, `refuelSteps`, `refuelStepMs`, `repairDuration`, `approachTimeout`, `returnTimeout`), `PitCrewIdleAnims`.

## Commands and keys

| Command | Who | Does |
|---|---|---|
| `/racestats` | anyone | Career stats |
| `/lobby` | anyone | Toggle focus on the lobby panel (same as the F2 key) |
| `/raceway` | Marshal and up | Raceway Control menu |

Key mapping `speedway_lobby_interact` (default F2) can be rebound in FiveM settings.

## Database

| Table | Purpose |
|---|---|
| `dps_roxwoodracing_stats` | One row per citizenid: `total_races`, `wins`, `top3`, `total_earnings`, `best_laps` (JSON keyed by layout, ms), `spec_wins`, `open_wins`, `last_race`. Created on boot; `speedway_stats` is renamed into it if present. |
| `dps_roxwoodracing_settings` | `k`/`v` staff overrides (`payout1..3`, `showup`, `bestlap`, `entryfee`). |

Reads elsewhere: `player_vehicles` (ownership checks, prize cars, plate uniqueness), `players.charinfo` (offline names on the LED sign), Renewed-Banking's own tables through its exports. The `ALTER TABLE … ADD COLUMN IF NOT EXISTS` migration is MariaDB syntax.

## Events, callbacks and exports

Prefix is `dps-roxwoodracing:`. Client → server events are validated and rate-limited server-side; nothing in the list below trusts client data for money, position, fuel or teleports.

**Client → server**

| Event | Payload | Notes |
|---|---|---|
| `createLobby` | `{ name, track, laps, mode, class, tune, vehicle? }` | Validated by `shared/validate.lua`; Open mode requires `vehicle = { netId, plate, class }`, verified against the live entity |
| `joinLobby` | `lobbyName, vehicle?` | Same Open checks; one car per plate per lobby; grid-slot limit |
| `leaveLobby` | | Refund before start; cleanup mid-race |
| `startRace` | `lobbyName` | Host only |
| `selectedVehicle` | `lobbyName, model` | Must be in the lobby's class group |
| `checkpointPassed` | `lobbyName, idx` | Strictly sequential |
| `lapPassed` | `lobbyName` | Only after every checkpoint |
| `updateProgress` | `lobbyName, dist` | Clamped, NaN-rejected, rate-limited |
| `server:setFuel` | `netId, level` | Only your own race car, inside a pit box |
| `staff:action` | `action, payload` | `endRace`, `clearProps`, `signMode` (Marshal), `setSetting` (Director) |

**Callbacks (ox_lib)**: `getLobbies`, `getLobbyPlayers`, `getSpecCatalogue`, `getOpenClasses`, `getPlayerStats`, `staff:snapshot` (staff only).

**Server → client**: `updateLobbyInfo`, `setLobbyState`, `hideLobbyWindow`, `chooseVehicle`, `vehicleSelectCountdown`, `prepareStart` (`{ track, laps, netId, plate, mode, tune, keepVehicle, grid? }`), `raceVehicles`, `client:unghost`, `client:setGhosted`, `updateLap`, `updatePosition`, `finalRanking`, `youFinished`, `client:finishTeleport(coords, keepVehicle)`, `client:destroyprops`, `kickedFromLobby`, `client:rewardNotify`, `client:statsNotify`, `client:notify`, `client:giveKeys`, `client:fillFuel`, `client:setFuel`, `client:openControl`, `setPlayerNames`, `setPlayerTimes`, `setText`, `setAdUrls`.

**Exports (server)**: `ShowIdleLeaderboard()`, `StopIdleLeaderboard()`.

**Internal events**: `dps-roxwoodracing:recordSet` (server, fired when a best lap is beaten; the idle sign listens), `amir-leaderboard:setPlayerNames/Times/Text/AdUrls` (server, the sign's API kept from the original).

## Layout

```
fxmanifest.lua
bridge/         framework detection (init), server API (player, money, job), client job lookups
integrations/   one file per vendor with a boot-time detect and a fallback:
                notify, target, keys, fuel (client) · banking, garages (server) · bossmenu (both)
shared/         pure modules, no natives at load: locale, validate, plates, tune, payouts, ranking
config/         config, tracks, vehicles, economy, pit
client/         main (lobby + race flow), hud (NUI), ghost, pit (zones), customs (style + tune), leaderboard (DUI)
server/         lobbies (catalogue, ownership), race (lobbies, laps, ranking, finish, drops), rewards, stats, staff, leaderboard
html/           index.html (lobby panel, HUD, results), led.html (sign), LCD font, ad images
stream/         LED sign model and placement
locales/en.lua
tests/          lua5.4 runner, stubs, test_*.lua · tools/check.sh
docs/           install.md, superpowers/specs, superpowers/plans
```

## Tests

```
./tools/check.sh
```

Syntax-checks every Lua file with `luac5.4 -p`, then runs `tests/run.lua`, which loads `tests/stubs.lua` (fake `exports`, `MySQL`, `GetResourceState`, events) and every `tests/test_*.lua`. Needs Lua 5.4 on the machine. Covered: config loading, bridge detection and money/job calls, client and server integrations, validation, plates, tune, payouts (purse covered / short / solo), ranking, rewards flows, stats migration, catalogue building, ownership checks, staff permissions and caps.

## Security model

- The server owns lobbies, timing, positions, payouts and teleports. Clients only report checkpoint crossings and a distance figure; the server enforces order, clamps values and rate-limits every event.
- Money never moves on a client's say-so: fees, refunds, pool, purse and prize cars are computed and paid server-side through the banking integration, with the ledger as the record.
- Open-mode cars are verified against the live entity (type, plate, driver seat) and the database (ownership) before they count. Vehicle class is read from the registry by model hash; for base-game cars not in the registry the client's class is accepted, which is the one known gap.
- Fuel sync is accepted only for the sender's own race car while it sits in a pit box.
- Staff actions are checked server-side against job and grade; settings have a ceiling.
- Everything the NUI renders goes through `textContent`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "The raceway account could not cover the purse" on every race | Account balance below the purse total, or a solo race | Deposit a float via the boss menu / bank, or set `purseSource = 'house'`; solo races always pay pool only |
| Spec menu shows only addon cars | Registry has no vanilla models | Add models to `Config.SpecFallbackVehicles`; they join the `Vanilla` group |
| `preset X has no registered vehicles; skipped` | None of the preset's models exist in the catalogue | Fix the model names or drop the preset |
| "Sit in a vehicle you own to join an Open race" | Not in the driver seat, plate not in your garage, or the car does not exist server-side | Sit in the driver seat of an owned car |
| Raceway Control says "Raceway staff only" | No `roxwoodracing` job | `/setjob <id> roxwoodracing <grade>` |
| Pit stop refuels visually but fuel drops back | Fuel vendor not detected | Check the client F8 line `[dps-roxwoodracing] fuel: …`; add the export to `integrations/fuel.lua` |
| Boss menu item missing | Not holding the job, or qbx_management absent | Item is registered only for the job's players; check the boot line `bossmenu: …` |
| LED sign blank | DUI failed or `Leaderboard.enabled = false` | Client F8 for `Loading leaderboard sign`; the ytyp/ymap in `stream/` must load |

## Credits and license

- Original script: MaxSuperTech (max_rox_speedway)
- rox_speedway: DrCannabis / DaemonAlex
- LED leaderboard: glitchdetector (amir-leaderboard)
- DPS port and hardening: DPS Development

License: see `LICENSE`.
