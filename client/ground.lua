-- Ground: put spawned cars and peds on the ground before they are frozen.
-- Roxwood streams in late. A ground snap that runs before the track's collision has
-- loaded fails without an error, and the freeze that follows then holds the car or ped
-- in the air. Everything here waits for collision first and reports whether it worked.

Ground = {}

-- Ground height under a point, or nil if none was found in time. Probes just above the
-- spot first so a pit-garage canopy or grandstand roof is not taken for the floor.
function Ground.Z(x, y, z, ms)
    local deadline = GetGameTimer() + (ms or 5000)
    repeat
        RequestCollisionAtCoord(x, y, z)
        for _, up in ipairs({ 1.0, 3.0, 5.0 }) do
            local found, gz = GetGroundZFor_3dCoord(x, y, z + up, false)
            if found then return gz end
        end
        Wait(50)
    until GetGameTimer() > deadline
    return nil
end

-- Put a vehicle on its wheels where it stands. True once it is on the ground.
function Ground.Vehicle(veh, ms)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    SetEntityLoadCollisionFlag(veh, true)
    local c = GetEntityCoords(veh)
    local deadline = GetGameTimer() + (ms or 5000)
    repeat
        RequestCollisionAtCoord(c.x, c.y, c.z)
        if HasCollisionLoadedAroundEntity(veh) and SetVehicleOnGroundProperly(veh) then return true end
        Wait(50)
    until GetGameTimer() > deadline or not DoesEntityExist(veh)
    return false
end

-- Stand a ped on the ground at x, y. True once it is on the ground.
function Ground.Ped(ped, x, y, z, ms)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local gz = Ground.Z(x, y, z, ms)
    if not gz or not DoesEntityExist(ped) then return false end
    SetEntityCoords(ped, x, y, gz, false, false, false, false)
    return true, gz
end
