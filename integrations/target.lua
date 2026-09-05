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
