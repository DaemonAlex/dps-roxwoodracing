-- /recordline <name>: a Race Director drives one lap; points are sampled every
-- Config.Practice.recordSpacing metres and saved server-side. /recordline again stops.
local recording, points, lineName = false, {}, nil

local function stopRecording()
  recording = false
  local n = #points
  if n < (Config.Practice.minPoints or 10) then
    Notify(Config.Job.label, Locale('line_too_short', n), 'error')
    points = {}
    return
  end
  TriggerServerEvent('dps-roxwoodracing:line:save', lineName, points)
  points = {}
end

RegisterNetEvent('dps-roxwoodracing:line:saved', function(ok, msg)
  Notify(Config.Job.label, msg, ok and 'success' or 'error', 8000)
end)

RegisterCommand('recordline', function(_, args)
  if not Bridge.HasJob(Config.Job.name, Config.Job.grades.director) then
    Notify(Config.Job.label, Locale('staff_only'), 'error')
    return
  end
  if recording then stopRecording() return end
  local name = (args[1] or 'main'):lower()
  if name == 'stop' then return end
  if not name:match('^[a-z0-9_]+$') or #name > 40 then
    Notify(Config.Job.label, Locale('line_bad_name'), 'error')
    return
  end
  if GetVehiclePedIsIn(PlayerPedId(), false) == 0 then
    Notify(Config.Job.label, Locale('line_need_vehicle'), 'error')
    return
  end
  lineName, points, recording = name, {}, true
  Notify(Config.Job.label, Locale('line_recording', name), 'inform', 9000)

  -- Bounded sampler: only runs while a recording is in progress.
  CreateThread(function()
    local last
    local spacing = Config.Practice.recordSpacing or 12.0
    local maxPoints = Config.Practice.maxPoints or 2000
    while recording do
      local veh = GetVehiclePedIsIn(PlayerPedId(), false)
      if veh ~= 0 then
        local c = GetEntityCoords(veh)
        if not last or #(c - last) >= spacing then
          points[#points + 1] = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(veh) }
          last = c
          if #points % 50 == 0 then Notify(Config.Job.label, Locale('line_progress', #points), 'inform', 2000) end
          if #points >= maxPoints then stopRecording() end
        end
      end
      Wait(100)
    end
  end)
end, false)

AddEventHandler('onResourceStop', function(res)
  if res == GetCurrentResourceName() then recording = false end
end)
