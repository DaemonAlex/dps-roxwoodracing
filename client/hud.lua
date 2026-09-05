-- NUI race HUD. Pushed on change only; no per-frame drawing.
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
