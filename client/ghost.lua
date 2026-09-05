-- Ghosting: no-collision + alpha against the other race cars. The per-frame loop exists
-- only while ghosted during a race and exits with either condition.
Ghost = { active = false, netIds = {}, myVeh = nil }

function Ghost.SetRaceVehicles(list) Ghost.netIds = list or {} end

function Ghost.Stop()
  Ghost.active = false
end

function Ghost.Start(myVeh)
  if myVeh then Ghost.myVeh = myVeh end
  if Ghost.active then return end
  Ghost.active = true
  local ghostEntities = {}
  CreateThread(function()
    while Ghost.active and IsRaceActive() do
      if Ghost.myVeh and DoesEntityExist(Ghost.myVeh) then
        for _, ent in ipairs(ghostEntities) do
          if DoesEntityExist(ent) then SetEntityNoCollisionEntity(Ghost.myVeh, ent, true) end
        end
      end
      Wait(0)
    end
  end)
  CreateThread(function()
    while Ghost.active and IsRaceActive() do
      local resolved = {}
      for _, v in ipairs(Ghost.netIds) do
        local other = NetworkGetEntityFromNetworkId(v.netId)
        if DoesEntityExist(other) and other ~= Ghost.myVeh then
          resolved[#resolved+1] = other
          SetEntityAlpha(other, Config.Ghosting.ghostAlpha, false)
        end
      end
      ghostEntities = resolved
      Wait(200)
    end
    for _, v in ipairs(Ghost.netIds) do
      local o = NetworkGetEntityFromNetworkId(v.netId)
      if DoesEntityExist(o) then ResetEntityAlpha(o) end
    end
    Ghost.active = false
  end)
end

RegisterNetEvent('dps-roxwoodracing:raceVehicles', function(list) Ghost.SetRaceVehicles(list) end)
RegisterNetEvent('dps-roxwoodracing:client:unghost', function() Ghost.Stop() end)
RegisterNetEvent('dps-roxwoodracing:client:setGhosted', function(on) if on then Ghost.Start(nil) else Ghost.Stop() end end)
