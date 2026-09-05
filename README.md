# dps-roxwoodracing

Roxwood Raceway for Del Perro Sands. Lobby-based racing with two modes, pit crews, an in-world LED leaderboard, persistent stats, and a real business behind it: the `roxwoodracing` job, whose society account takes the entry fees and pays the purses.

Descended from [max_rox_speedway](https://github.com/MaxSuperTech/max_rox_speedway) (MaxSuperTech) via rox_speedway (DrCannabis / DaemonAlex). Version 3.0 is the DPS port; see `CHANGELOG.md`.

## What it does

- **Lobbies.** Walk up to the paddock ped, create or join. Host starts the countdown. Four layouts (Short, Drift, Speed, Long) with checkpoint ranking that stays accurate through curves. Concurrent races on different layouts.
- **Spec mode.** The raceway spawns the cars. Any vehicle the server registers is on the menu, grouped by class, plus the old curated presets. The host picks a lobby-wide tune: Stock, Street, or Race. Cars are deleted after the race.
- **Open mode.** Bring a car you own. The server checks the plate is yours and that it fits the class the host chose. You keep the car afterwards, damage and all.
- **Pit crews.** NPC crews refuel and repair when you stop in a pit box.
- **Ghosting, results screen, best-lap and most-improved badges, LED sign** as before.
- **Money.** Entry fee goes into the `roxwoodracing` society account. The buy-in pool (60/30/10) and the podium purse (5000/3000/1500, show-up 500, fastest lap 1000) are paid out of that account. If the account cannot cover the purse, the race pays the pool only and says so. `purseSource = 'house'` mints the purse instead but still logs it.
- **Staff.** Marshals end stuck races, clear props and switch the sign; Race Directors set fees and purse; the Owner has the boss menu and bank access. `/raceway` or the boss-menu item "Raceway Control".

## Requirements

ox_lib, oxmysql, and a framework (qbx_core first, qb-core, es_extended). Everything else is detected at boot and falls back:

| Need | Detected | Fallback |
|---|---|---|
| Society money | Renewed-Banking | qb-banking, then plain player cash |
| Boss menu | qbx_management | qb-bossmenu event |
| Prize car | jg-advancedgarages (`garage_id`) | stock `garage` column |
| Keys | wasabi_carlock | qs-vehiclekeys, Renewed-Vehiclekeys, qb-vehiclekeys, unlock only |
| Fuel | ox_fuel statebag | LegacyFuel, cdn-fuel, okokGasStation, qs-fuelstations, natives |
| Target | ox_target | qb-target, proximity key |
| Notify | ox_lib | okokNotify, console |

Install steps for DPS (job entry, garage entry) are in `docs/install.md`.

## Configuration

| File | Holds |
|---|---|
| `config/config.lua` | timing, keybind, debug, leaderboard, ghosting, results UI |
| `config/tracks.lua` | checkpoints, segment hints, props, grid, finish line, paddock ped |
| `config/vehicles.lua` | spec presets, fallback list, `Config.OpenClasses`, `Config.Tune` |
| `config/economy.lua` | `Config.Job`, `Config.Economy` (fees, purse, pool split, prize car) |
| `config/pit.lua` | pit boxes, crew model, timings |

Tune presets are mod indices: Street = engine/brakes/gearbox 2, Race = max of each plus turbo. Add or change them in `Config.Tune`; the order shown in the menu is `Config.TuneOrder`.

## Commands

| Command | Who | Does |
|---|---|---|
| `/racestats` | anyone | career stats |
| `/lobby` | anyone | toggle the lobby panel focus (F2 by default) |
| `/raceway` | Marshal and up | Raceway Control menu |

## Layout

```
bridge/         framework detection + player/money/job API
integrations/   one file per vendor: notify, target, keys, fuel, banking, garages, bossmenu
shared/         pure modules (validate, plates, tune, payouts, ranking, locale) — unit-tested
config/         split by topic
client/         main, hud, ghost, pit, customs, leaderboard
server/         lobbies, race, rewards, stats, staff, leaderboard
html/           lobby + HUD + results page, LED renderer
stream/         LED sign model
tests/          lua5.4 runner and stubs; tools/check.sh runs syntax + tests
```

## Database

`dps_roxwoodracing_stats` (auto-created; `speedway_stats` is renamed on first boot if present) and `dps_roxwoodracing_settings` (staff overrides). `best_laps` is JSON keyed by track name, times in milliseconds.

## Tests

```
./tools/check.sh
```

Syntax-checks every Lua file with `luac5.4 -p`, then runs `tests/run.lua`. Needs Lua 5.4 on the machine.

## Credits

- Original script: MaxSuperTech (max_rox_speedway)
- rox_speedway: DrCannabis / DaemonAlex
- LED leaderboard: glitchdetector (amir-leaderboard)
- DPS port: DPS Development

## License

See `LICENSE`.
