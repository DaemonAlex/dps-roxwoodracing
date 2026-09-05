# Install on Del Perro Sands

1. Resource lives at `resources/[dps]/dps-roxwoodracing`. `ensure [dps]` already covers it.
2. qbx_core `shared/jobs.lua` — add:

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

3. jg-advancedgarages `config/config.lua` → `Config.GarageLocations` — add:

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

   Coords are the paddock next to the lobby ped; adjust in-game once.
4. Full server reboot. The boot log must show one line each for framework, notify, target, keys, fuel, banking, garages, bossmenu, spec catalogue, stats table, staff settings.
5. The society account `roxwoodracing` is created on first boot with $0. Deposit a float before the first race, or set `Config.Economy.purseSource = 'house'` in `config/economy.lua`.
6. Tables: `dps_roxwoodracing_stats` (renamed from `speedway_stats` if that exists) and `dps_roxwoodracing_settings` are created automatically.
