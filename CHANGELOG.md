# Changelog

All notable changes to this project will be documented in this file.

## v2.4.2 — Multi-Lobby + Polish (2026-05-09)

### Concurrent races
Multiple lobbies can now run at the same time on different tracks. Previously, a single active lobby blocked all others server-wide. The new rule rejects only same-track collisions (e.g. you can't open a second Short_Track lobby while one is already racing there, but you can open a Drift_Track lobby while Short_Track is in use). The shared starting grid is automatically serialized — if two lobbies hit "Start Race" at the same instant, the second one waits a few seconds for the first race's cars to clear before spawning. The physical AMIR LED scoreboard follows the first lobby to start; concurrent lobbies still race normally but don't drive the LED board (the on-screen HUD remains for everyone). When the primary lobby ends, the next running lobby is automatically promoted.

### RP-friendly names
The lobby panel, the live AMIR scoreboard, and the post-race results screen now show framework character names (e.g. "John Smith" via ESX/QBCore) instead of Steam display names. Standalone servers and any framework where the bridge can't resolve a character name fall back to the previous behavior automatically.

### Translations
The three error messages added in v2.4.1 ("Invalid lobby name", "Invalid track selection", "Invalid lap count") and the new `track_in_use` message now have proper Spanish, French, German, and Russian translations instead of being hardcoded English.

### Performance
End-of-race database saves are noticeably faster on full grids:
- Removed the per-player read-back query — the script now computes the new totals locally from the row it already fetched, saving one round-trip per finisher.
- Each player's stat save runs in its own thread, so the per-player DB work overlaps instead of serializing.
- For an 8-player race: 24 serial queries → 16 parallelized queries.

### Cleanups
- Deduplicated three near-identical `updateLobbyInfo` payload constructions into a single `buildLobbyInfo` helper.
- Fixed a small memory leak: `amirState[lobbyName]` was retained after a lobby was destroyed; now cleared on race-end and on owner-leaves.
- Added `oxmysql` to `dependencies` in fxmanifest (the `@oxmysql` import already enforced load order — this is documentation polish so server admins can see the requirement at a glance).

### Files Changed
- `server/s_main.lua` — multi-lobby coordination, RP names, locale wiring, DB perf, helper extraction, memory cleanup
- `client/c_main.lua` — prefer server-supplied character names in the lobby panel
- `locales/en.lua`, `es.lua`, `fr.lua`, `de.lua`, `ru.lua` — `invalid_lobby_name`, `invalid_track`, `invalid_laps`, `track_in_use`
- `fxmanifest.lua` — declared `oxmysql` dependency

---

## v2.4.1 — Lobby Creation Hotfix (2026-05-09)

Fix silent failure when creating a lobby. The auto-generated lobby name was built directly from `GetPlayerName()`, which often contains spaces, brackets, dots, or other characters that the server-side validator rejects (alphanumeric/underscore only). The validator returned silently with no notification, so players saw the dialog close and nothing happen.

### Files Changed
- `client/c_main.lua` — sanitize the player display name to `[A-Za-z0-9_]` before composing the lobby name; cap at 30 chars; fall back to `Racer` if empty
- `server/s_main.lua` — the lobby name / track / lap count validators in `speedway:createLobby` now send a `ServerNotify` before returning, so any future validation failure is visible instead of silent

No config, locale, or framework-bridge changes. Affects all frameworks (QBCore / Qbox / ESX / standalone) since the failure was on the validation path, not in the bridge.

---

## v2.4 — UI Restyle (2026-03-06)

Replaced generic Tailwind-derived colors with a custom motorsport/F1 timing screen palette. The UI now uses a darker carbon background, cyan ghost buttons with glow hover states, and tighter border radii throughout — closer to a proper race timing display than a generic web app.

### Visual
- **Font**: switched to Barlow Condensed / Barlow (Google Fonts) — narrow, technical, commonly used in motorsport design
- **Buttons**: replaced solid blue (#2563eb) fills with frosted cyan ghost style — translucent cyan background, cyan text, outlined border, glow on hover
- **Secondary buttons**: neutral translucent white instead of gray-700
- **Modal card**: darker background (#0d1017), consistent rgba borders instead of gray hex values
- **Results card**: tighter radius (18px → 8px), same cyan button treatment
- **Tablet/lobby panel**: radius 18px → 10px
- **All border-radius values**: tightened across the board (10px → 6px on cards, 8px → 4px on buttons)
- **Badge "Most Improved"**: slightly brighter green (#00c853 → #00e676)

### Files Changed
- `client/nui/timeout.html` — full color/font/radius overhaul
- `client/nui/lobby.html` — font and radius updates for consistency
- `README.md` — rewritten

### Removed Colors
No more raw Tailwind hex values in the UI: `#2563eb`, `#1d4ed8`, `#374151`, `#111827`, `#e5e7eb` are all gone.

---

## v2.3 — "Quality of Racing" (2026-03-02)

### Ghosting System
- **Start-of-race ghosting**: all racers are ghosted at GO to prevent first-corner pile-ups
- **Checkpoint-based unghost**: ghosting ends when ALL racers pass checkpoint 1 (configurable)
- **Timer fallback**: auto-unghost after 15 seconds if checkpoint condition isn't met
- **Lapped-player ghosting**: players a full lap behind the leader become ghosted to prevent griefing
- **Dual-speed client thread**: fast per-frame collision disable + slow 200ms alpha/entity resolution for performance
- Fully configurable via `Config.Ghosting` (can be disabled entirely)

### Race Summary UI
- **NUI results overlay** replaces notification toasts after race finishes
- Shows all drivers with position, total time, best lap, and payout
- **Podium styling**: gold/silver/bronze accents for top 3 positions
- **Best Lap badge**: star icon on the driver with the fastest single lap
- **Most Improved badge**: arrow icon on the driver who gained the most positions from grid to finish
- Auto-dismisses after 20 seconds (configurable), or close via ESC / Close button
- Falls back to legacy toast notifications when `Config.ResultsUI.enabled = false`

### Server Changes
- `SpawnRaceVehicles()` now broadcasts all race vehicle netIds to clients
- Grid order recorded at spawn for "Most Improved" calculation
- Expanded `speedway:finalRanking` payload includes name, bestLap, lapTimes, payout, gridPosition, badges
- Lapped-player detection in `speedway:updateProgress` handler

### New Net Events
- `speedway:raceVehicles` (S→C): share all race vehicle netIds
- `speedway:client:unghost` (S→C): end start-of-race ghost period
- `speedway:client:setGhosted` (S→C): toggle lapped-player ghost state

### Files Changed
- `config/config.lua` — added `Config.Ghosting` and `Config.ResultsUI`
- `server/s_main.lua` — netId broadcast, ghost timer, checkpoint unghost, lapped ghost, expanded results
- `client/c_main.lua` — ghost thread, unghost handlers, NUI results forwarding, cleanup
- `client/nui/timeout.html` — results overlay HTML/CSS/JS
- `CHANGELOG.md` — this entry

---

## 2025-11-03

Summary of changes derived from `NOTES.md`.

- HUD & Laps
  - Lap HUD now initializes to `1/x` at race start based on `speedway:prepareStart` payload (no local shadowing).
  - Server always includes `laps` in `speedway:prepareStart` payloads.

- Ranking
  - Server sorts racers by `lap > checkpoint > distance`.
  - Display inversion remains configurable via `Config.RankingInvert` (default `false`).

- Distance Metric
  - Improved monotonic progress tracking with virtual segments around Start/Finish.
  - Smoothing near checkpoints to avoid jitter.

- Debugging
  - Split debug controls:
    - `Config.DebugPrints` — console [DEBUG] logs (client/server). Default: `false`.
    - `Config.ZoneDebug` — lib.zones/polyzone visualization (red spheres). Default: `false`.
  - Deprecated: `Config.debug` (previous catch-all). Prefer the two new toggles above.

- UI/UX
  - Lobby overlay hides on prepare/start.
  - Selection countdown + auto-kick for AFK.
  - Blocking modal on kick.
  - Safer qb-input close and focus handling.

- Files impacted
  - `client/c_main.lua` — HUD lap init; distance metric; debug gating; zone debug visualization.
  - `server/s_main.lua` — Always include `laps` in start payload; debug gating.
  - `config/config.lua` — Added `DebugPrints` and `ZoneDebug`; kept `RankingInvert`.

### Validation checklist

- Restart the resource.
- Start a 3‑lap race:
  - HUD should display `Lap: 1/3` immediately at the start.
  - No console spam unless `Config.DebugPrints = true`.
  - Set `Config.ZoneDebug = true` if you want checkpoint/finish spheres for testing.
