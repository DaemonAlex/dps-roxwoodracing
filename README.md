# rox_speedway

Multiplayer race system for FiveM built around Roxwood Speedway. Lobby-based, supports race classes, rewards, persistent stats, ghosting, pit crews, and a physical LED leaderboard sign.

Originally forked from [max_rox_speedway by MaxSuperTech](https://github.com/MaxSuperTech/max_rox_speedway) - heavily rewritten since.

---

## Getting Started

You'll need these already running on your server:
- [ox_lib](https://github.com/overextended/ox_lib)
- [qb-core](https://github.com/qbcore-framework/qb-core) or [qbx_core](https://github.com/Qbox-project/qbx_core) (or ESX - auto-detected)
- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_target](https://github.com/overextended/ox_target) or [qb-target](https://github.com/qbcore-framework/qb-target) (set in config)

Drop the `rox_speedway` folder into your resources, add `ensure rox_speedway` to your `server.cfg`, and restart. The database table creates itself on first boot. Walk up to the NPC at the speedway and you're racing.

Defaults are sane - rewards on, entry fees off, stats tracking on. Tweak `config/config.lua` when you feel like it.

---

## What It Does

**Racing**
- Create and join lobbies, host starts the countdown
- 4 track layouts (Short, Drift, Speed, Long) with segment hints for accurate position tracking through curves
- Live position HUD during races
- Full lap timing with podium results
- Pit crew NPCs that refuel and repair your car mid-race
- 75+ curated vehicles across 7 race classes

**Ghosting**
Prevents the usual first-corner pile-up and lapped-player griefing. Everyone's ghosted at GO, then unghosted once all racers pass the first checkpoint (or after a 15-second timer). Players a full lap behind the leader get ghosted too so they can't block. Configurable or disable entirely.

**Race Results Screen**
Full results overlay after each race - positions, times, best laps, payouts, podium styling (gold/silver/bronze for top 3), and badges for fastest lap and most improved driver. Replaces the old notification toasts. Auto-dismisses after 20 seconds.

**Race Classes**

| Class | Examples |
|-------|----------|
| Open | All 75+ vehicles |
| Super Cars | Krieger, Emerus, Deveste Eight, Thrax, Cyclone, Ignus |
| Tuners / JDM | Calico GTF, Jester RR, ZR350, Sultan RS Classic, Futo GTX |
| Muscle | Dominator GT, Gauntlet Hellfire, Buffalo STX |
| Motorcycles | Hakuchou Drag, Bati 801RR, Shinobi, Reever |
| Vans & Trucks | Youga Custom, Yosemite 1500, Sandking XL, Kamacho |
| Rally | Omnis, GB200, Tropos Rallye, WRC i20, Yaris WRC |

You can add your own - just drop a new entry in `Config.RaceClasses` with a label and vehicle list.

**Rewards & Entry Fees**
- 1st: $5,000 / 2nd: $3,000 / 3rd: $1,500 / participation: $500 / fastest lap: $1,000
- Optional vehicle prize for 1st (saved to their garage)
- Optional entry fee system - buy-in pool splits 60/30/10 to top 3
- Both systems stack if you want

**Persistent Stats**
Career tracking in the database - wins, podiums, total races, lifetime earnings, best lap per track. Players check their stats with `/racestats`. Records trigger a "NEW RECORD" notification.

**LED Leaderboard**
Physical sign at the speedway. Shows live positions during races, top 9 all-time records when idle. Based on [glitchdetector's amir-leaderboard](https://github.com/glitchdetector/amir-leaderboard), bundled directly so there's no separate resource to install.

**Localization**
Ships with English, Spanish, French, German, and Russian. Add your own by dropping a new file in `locales/`.

---

## Tracks

| Track | Checkpoints | Notes |
|-------|-------------|-------|
| Short_Track | 3 | Quick inner oval, fastest laps |
| Drift_Track | 3 | Extended route with wide sweeping turns |
| Speed_Track | 4 | Outer oval for high-speed runs |
| Long_Track | 5 | Full circuit combining all sections |

---

## Commands

| Command | Description |
|---------|-------------|
| `/racestats` | View your career stats |
| `/lobby` | Toggle lobby interaction (backup for keybind) |
| `/speedway_cleanup` | Force-clean track props and zones |
| `/lb names` | Switch leaderboard to names mode |
| `/lb toggle` | Switch leaderboard to toggle mode |

Default lobby interact key is **F2** - players can rebind it in FiveM settings.

---

## Configuration

Everything lives in `config/config.lua`. Here's what you can change:

### Rewards

```lua
Config.Rewards = {
    enabled = true,
    moneyType = 'cash',              -- 'cash' or 'bank'
    payouts = {
        [1] = 5000,
        [2] = 3000,
        [3] = 1500,
    },
    participationReward = 500,
    bestLapBonus = 1000,
    vehiclePrize = nil,              -- model name like 'krieger' to award a car
    vehiclePrizeGarage = 'pillboxgarage',
}
```

### Entry Fees

```lua
Config.EntryFee = {
    enabled = false,                 -- flip to true for buy-ins
    amount = 1000,
    moneyType = 'cash',
    poolSplit = { [1] = 60, [2] = 30, [3] = 10 },
}
```

### Stats

```lua
Config.Stats = {
    enabled = true,
    showAfterRace = true,
}
```

The `speedway_stats` table is created automatically - no SQL to run.

### Ghosting

```lua
Config.Ghosting = {
    enabled = true,
    startGhosted = true,
    unghostOnCheckpoint = 1,         -- 0 = timer only
    unghostTimerSeconds = 15,
    lappedGhosting = true,
    ghostAlpha = 150,                -- 0-255
}
```

### Results UI

```lua
Config.ResultsUI = {
    enabled = true,
    displayDurationMs = 20000,
    showBestLap = true,
    showMostImproved = true,
}
```

### Race Settings

```lua
Config.RaceStartDelay = 10
Config.ProgressTickMs = 150          -- 75-200ms recommended
Config.DistanceUseNoseCorners = true
```

### Targeting & Notifications

```lua
Config.TargetSystem = 'ox_target'    -- or 'qb-target'
Config.NotificationProvider = "ox_lib"  -- "okokNotify" or "rtx_notify"
```

### Pit Stop Timing

```lua
Config.PitStopTiming = {
    crewWalkSpeed    = 2.0,
    refuelSteps      = 15,
    refuelStepMs     = 200,
    repairDuration   = 3000,
    approachTimeout  = 8000,
    returnTimeout    = 15000,
}
```

### LED Leaderboard

```lua
Config.Leaderboard = {
    enabled = true,
    idleDisplay = true,
    updateIntervalMs = 1000,
    toggleIntervalMs = 2000,
    viewMode = "toggle",             -- or "names"
    timeMode = "total",              -- or "lap"
}
```

### Debug

```lua
Config.DebugPrints = false
Config.ZoneDebug = false
Config.RankingInvert = false
```

---

## Adding Your Own Stuff

### Custom Tracks

```lua
Config.Checkpoints = {
    My_Track = {
        vector3(x1, y1, z1),
        vector3(x2, y2, z2),
        vector3(x3, y3, z3),
    },
}

-- Optional but helps with ranking accuracy on curves
Config.SegmentHints = {
    My_Track = {
        [0] = { vector3(x, y, z) },
        [1] = { vector3(x, y, z) },
    },
}
```

### Custom Race Classes

```lua
Config.RaceClasses.Offroad = {
    label = "Off-Road",
    description = "Dirt and mud only",
    vehicles = { "kamacho", "riata", "sandking", "bf400", "manchez3" },
}
```

Vehicle names need to exist in `Config.RaceVehicles` or they won't show up in the selection menu.

---

## File Structure

```
rox_speedway/
  fxmanifest.lua
  config/
    config.lua
  client/
    c_main.lua              -- lobby UI, race HUD, vehicle selection, rewards display
    c_fuel.lua              -- fuel system detection
    c_keys.lua              -- vehicle key integration
    c_customs.lua           -- cosmetics & paint
    c_function.lua          -- shared utilities
    c_pit.lua               -- pit stop logic & crew animations
    nui/
      timeout.html          -- lobby overlay, timeout modal, race results UI
  server/
    s_main.lua              -- lobbies, race logic, rewards, stats, entry fees
    sv_bridge.lua           -- framework bridge (QBCore/QBX/ESX auto-detect)
  leaderboard/
    cl_leaderboard.lua      -- DUI setup for the in-world LED sign
    sv_leaderboard.lua      -- display state & idle best-times loop
    speedway.html           -- LED display renderer
    LCDMB___.TTF            -- LCD font
    ads/                    -- ad images for the sign
  stream/                   -- 3D model, textures, and map placement for the LED sign
  locales/
    en.lua, es.lua, fr.lua, de.lua, ru.lua
```

---

## Database

Auto-created on startup:

```sql
CREATE TABLE IF NOT EXISTS speedway_stats (
    citizenid VARCHAR(50) NOT NULL,
    total_races INT DEFAULT 0,
    wins INT DEFAULT 0,
    top3 INT DEFAULT 0,
    total_earnings INT DEFAULT 0,
    best_laps JSON DEFAULT '{}',
    last_race TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid)
);
```

`best_laps` is a JSON object keyed by track name: `{"Short_Track": 45200, "Drift_Track": 62100}` (times in milliseconds).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history. Recent highlights:

- **v2.4.2** - Multiple concurrent races on different tracks; RP character names in lobby/scoreboard/results; full translations for v2.4.1 errors; faster end-of-race DB saves
- **v2.4.1** - Hotfix: lobby creation no longer fails silently when player display name contains special characters
- **v2.4** - Motorsport UI restyle, custom font (Barlow Condensed), tighter design language
- **v2.3** - Ghosting system, race results overlay, expanded results payload
- **v2.2** - Server-side input validation, anti-cheat hardening, memory optimizations
- **v2.1** - Bundled LED leaderboard, idle best-times display
- **v2.0** - Race classes, rewards, entry fees, persistent stats, 75+ vehicles

---

## Dependencies

**Required:** [ox_lib](https://github.com/overextended/ox_lib) / [oxmysql](https://github.com/overextended/oxmysql) / QBCore, Qbox, or ESX (auto-detected)

**Target (one of):** [ox_target](https://github.com/overextended/ox_target) or [qb-target](https://github.com/qbcore-framework/qb-target)

**Bundled:** [AMIR Leaderboard](https://github.com/glitchdetector/amir-leaderboard) by glitchdetector

## Credits

- Original script: [MaxSuperTech](https://github.com/MaxSuperTech/max_rox_speedway)
- LED leaderboard: [glitchdetector](https://github.com/glitchdetector/amir-leaderboard)
- Maintained by DrCannabis / DaemonAlex

## License

See [LICENSE](LICENSE).
