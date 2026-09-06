-- client/c_pit.lua

if Config.DebugPrints then print("[dps-roxwoodracing] c_pit.lua loaded") end

-- Config is a shared global

-- will hold all our ped references
local pitZones = {}
local pitBlips = {}
local inPit = false   -- true while a pit stop sequence is running (see section 3)

--------------------------------------------------------------------------------
-- 1) SPAWN ALL PIT CREW
--------------------------------------------------------------------------------
-- Load one ped model with a timeout; returns the hash, or nil if this client lacks it.
local function loadPedModel(name, timeoutMs)
    local hash = joaat(name)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    if HasModelLoaded(hash) then return hash end
    return nil
end

-- Every configured crew model that exists on this client. Falls back to one vanilla
-- mechanic so the crew always spawns even on a client missing every addon ped.
local function buildModelPool()
    local pool, seen = {}, {}
    local names = {}
    if Config.PitCrewModel then names[#names + 1] = Config.PitCrewModel end  -- legacy single-model setting
    for _, n in ipairs(Config.PitCrewModels or {}) do names[#names + 1] = n end
    for _, name in ipairs(names) do
        if not seen[name] then
            seen[name] = true
            local hash = loadPedModel(name, 5000)
            if hash then
                pool[#pool + 1] = hash
            elseif Config.DebugPrints then
                print(("[dps-roxwoodracing] pit crew model '%s' not available, skipping"):format(name))
            end
        end
    end
    if #pool == 0 then
        print("[dps-roxwoodracing] WARNING: no configured pit crew model loaded, using s_m_y_xmech_02")
        local hash = loadPedModel('s_m_y_xmech_02', 8000)
        if hash then pool[1] = hash end
    end
    return pool
end

-- Ground Z under a spawn point. The pit lane is normally far from the player when this
-- runs (player load), so its collision is not streamed and the lookup fails; request the
-- collision first and retry briefly. Probe from +1.0 before +5.0 so a pit-garage canopy
-- above the box is not mistaken for the floor.
local function groundAt(x, y, z)
    local deadline = GetGameTimer() + 3000
    repeat
        RequestCollisionAtCoord(x, y, z)
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
        if not found then found, gz = GetGroundZFor_3dCoord(x, y, z + 5.0, false) end
        if found then return gz, true end
        Wait(50)
    until GetGameTimer() > deadline
    return z, false
end

local function spawnCrewPed(pool, pos, heading)
    local hash = pool[math.random(#pool)]
    local gz, onGround = groundAt(pos.x, pos.y, pos.z)
    local ped = CreatePed(4, hash, pos.x, pos.y, gz, heading, false, false)
    SetPedRandomComponentVariation(ped, 0)  -- random outfit within the model
    SetPedRandomProps(ped)                   -- random hats/glasses
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    return ped, vector3(pos.x, pos.y, gz), onGround
end

-- Second chance for peds whose ground lookup failed at spawn: once the player is close
-- enough for the pit lane collision to be streamed, re-snap every idle crew member.
local function resnapZone(idx)
    local data = pitZones[idx]
    if not data or inPit then return end
    local deadline = GetGameTimer() + 5000
    local probe = data.idle[1] or data.crew[1]
    while probe and DoesEntityExist(probe) and not HasCollisionLoadedAroundEntity(probe) and GetGameTimer() < deadline do
        Wait(100)
    end
    for ped, home in pairs(data.home) do
        if DoesEntityExist(ped) and not inPit then
            local found, gz = GetGroundZFor_3dCoord(home.x, home.y, home.z + 1.0, false)
            if found and math.abs(gz - home.z) > 0.05 then
                local fixed = vector3(home.x, home.y, gz)
                SetEntityCoords(ped, fixed.x, fixed.y, fixed.z, false, false, false, false)
                data.home[ped] = fixed
                if data.crewHome[ped] then data.crewHome[ped] = fixed end
                if Config.DebugPrints then print(("[dps-roxwoodracing] re-snapped pit ped to ground (%.2f -> %.2f)"):format(home.z, gz)) end
            end
        end
    end
end

CreateThread(function()
    Wait(100)

    if Config.DebugPrints then print(("[dps-roxwoodracing] Config.PitCrewZones has %d entries"):format(#Config.PitCrewZones)) end

    local pool = buildModelPool()
    if #pool == 0 then
        print("[dps-roxwoodracing] ERROR: could not load any pit crew ped model; aborting pit crew spawn")
        return
    end

    for idx, zone in ipairs(Config.PitCrewZones) do
        if Config.DebugPrints then print(("[dps-roxwoodracing] Spawning pit crew for zone %d at %s"):format(idx, tostring(zone.coords))) end
        pitZones[idx] = { idle = {}, crew = {}, crewIdle = {}, crewHome = {}, home = {}, spawnHeading = 0.0 }
        local data = pitZones[idx]

        -- Support vec4 coords (x,y,z,w) where w is the zone heading; fallback to explicit 'heading'
        local zoneHeading = (zone.coords and zone.coords.w) or zone.heading or 0.0
        data.spawnHeading = zoneHeading

        local r = zone.radius
        -- Wall lineup offsets (local X along the wall, Y = distance from zone center to wall)
        -- Evenly spaced: [-3.2, -1.6, 0.0, +1.6, +3.2] to avoid 'pairing' and keep a tidy line.
        local idleBase = { vector3(-3.2, r, 0.0), vector3(3.2, r, 0.0) }
        local crewBase = { vector3(-1.6, r, 0.0), vector3(0.0, r, 0.0), vector3(1.6, r, 0.0) }
        local angle = math.rad(-10)
        local cosA, sinA = math.cos(angle), math.sin(angle)
        local moveOffset = vector3(-0.68, -3.17, 0.0)
        local grounded = 0

        -- idle peds
        for i, base in ipairs(idleBase) do
            local x = base.x * cosA - base.y * sinA
            local y = base.x * sinA + base.y * cosA
            local pos = zone.coords + vector3(x, y, base.z) + moveOffset
            local ped, home, onGround = spawnCrewPed(pool, pos, zoneHeading)
            if onGround then grounded = grounded + 1 end
            -- Random idle animation from config for variety
            local idleAnims = Config.PitCrewIdleAnims or { "WORLD_HUMAN_STAND_IMPATIENT" }
            TaskStartScenarioInPlace(ped, idleAnims[math.random(1, #idleAnims)], 0, true)
            data.idle[i] = ped
            data.home[ped] = home
        end

        -- service peds
        for i, base in ipairs(crewBase) do
            local x = base.x * cosA - base.y * sinA
            local y = base.x * sinA + base.y * cosA
            local offs = vector3(x, y, base.z)
            local pos = zone.coords + offs + moveOffset
            local ped, home, onGround = spawnCrewPed(pool, pos, zoneHeading)
            if onGround then grounded = grounded + 1 end
            TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
            data.crew[i]       = ped
            data.crewIdle[i]   = offs + moveOffset
            data.crewHome[ped] = home
            data.home[ped]     = home
        end

        if Config.DebugPrints then
            print(("[dps-roxwoodracing] pit zone %d: %d/%d peds placed on found ground"):format(idx, grounded, #idleBase + #crewBase))
        end

        -- Re-snap to the ground when a player first gets near (collision streamed by then)
        data.point = lib.points.new({
            coords = vector3(zone.coords.x, zone.coords.y, zone.coords.z),
            distance = 120.0,
            onEnter = function() CreateThread(function() resnapZone(idx) end) end,
        })

        -- Blips disabled per server policy (static blips managed centrally)
    end

    for _, hash in ipairs(pool) do SetModelAsNoLongerNeeded(hash) end
end)

-- Cleanup on resource stop to avoid orphan peds and blips
AddEventHandler('onClientResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for _, zone in pairs(pitZones) do
        if zone.idle then
            for _, p in ipairs(zone.idle) do if DoesEntityExist(p) then DeleteEntity(p) end end
        end
        if zone.crew then
            for _, p in ipairs(zone.crew) do if DoesEntityExist(p) then DeleteEntity(p) end end
        end
        if zone.point then zone.point:remove() end
    end
    -- Blips removed (static blips disabled per policy)
end)

--------------------------------------------------------------------------------
-- 2) HELPER: FIND NEAREST ZONE INDEX
--------------------------------------------------------------------------------
local function getNearestZoneIdx(veh)
    local vcoords, bestIdx, bestDist = GetEntityCoords(veh), nil, math.huge
    for idx, zone in ipairs(Config.PitCrewZones) do
        local d = #(vcoords - zone.coords)
        if d < bestDist then bestDist, bestIdx = d, idx end
    end
    return bestIdx
end

--------------------------------------------------------------------------------
-- 3) AUTOMATIC PIT DETECTION & SERVICE SEQUENCE
--------------------------------------------------------------------------------
-- inPit is declared at the top of this file (shared with the spawn/resnap code)
local pitCooldownUntil = 0  -- GetGameTimer timestamp: block re-entry until this time
local fuelBones = { "door_fuel", "petrolcap", "petroltank" }
local canModel = GetHashKey("prop_jerrycan_01a")

-- The full service sequence for pit box `idx`. Body ported verbatim from the old scan loop.
local function RunPitStop(veh, idx)
    local zoneData   = pitZones[idx]
    local zoneCfg    = Config.PitCrewZones[idx]
    local baseCoords = zoneCfg.coords

    -- snap vehicle to pit slot and freeze (keep current heading)
    SetEntityCoordsNoOffset(veh, baseCoords.x, baseCoords.y, baseCoords.z, false, false, false)
    SetVehicleOnGroundProperly(veh)
    FreezeEntityPosition(veh, true)

    -- unfreeze crew
    for _, cp in ipairs(zoneData.crew) do FreezeEntityPosition(cp, false) end

    -- compute service positions using vehicle bones and vectors for reliability
    -- direction helpers
    local fwd = GetEntityForwardVector(veh)
    -- compute vehicle-right vector (perpendicular to forward)
    local rightVec = vector3(fwd.y, -fwd.x, 0.0)
    do
        local mag = math.sqrt(rightVec.x*rightVec.x + rightVec.y*rightVec.y + rightVec.z*rightVec.z)
        if mag > 0.001 then rightVec = vector3(rightVec.x/mag, rightVec.y/mag, rightVec.z/mag) end
    end

    -- Fuel: driver-side rear (left + rear relative to vehicle)
    local drv = GetOffsetFromEntityInWorldCoords(veh, -1.2, -2.0, 0.0)
    local dfound, dz = GetGroundZFor_3dCoord(drv.x, drv.y, drv.z + 3.0, false)
    local fuelPos = vector3(drv.x, drv.y, dfound and dz or drv.z)

    -- Hood mechanic: stand centered in front of the car, a bit away from the bumper
    local frontPos = GetOffsetFromEntityInWorldCoords(veh, 0.0, 2.2, 0.0)
    local bonnetIdx = GetEntityBoneIndexByName(veh, "bonnet")
    if bonnetIdx ~= -1 then
        local bpos = GetWorldPositionOfEntityBone(veh, bonnetIdx)
        -- step the hood ped a bit farther away from the car
        frontPos = bpos + (fwd * 1.6)
    end
    -- this places the hood ped in front of center, stepped out from the bumper

    -- Tire checker: prefer front-right wheel bone to guarantee passenger side
    local sidePos  = GetOffsetFromEntityInWorldCoords(veh, 1.5, 0.0, 0.0)
    local wrIdx = GetEntityBoneIndexByName(veh, "wheel_rf")
    if wrIdx ~= -1 then
        local wpos = GetWorldPositionOfEntityBone(veh, wrIdx)
        -- Pull the passenger ped slightly away from the wheel and a touch rearward to prevent climbing
        sidePos = wpos + (rightVec * 0.75) - (fwd * 0.25)
    end

    -- approach points to reduce collision with the vehicle and each other
    local fuelApproach  = fuelPos - (fwd * 0.8) - (rightVec * 0.6)
    local frontApproach = frontPos + (fwd * 1.2)
    local sideApproach  = sidePos + (rightVec * 0.8)
    -- snap service points to ground to help navmesh pathing
    do
        local fzFound, fz = GetGroundZFor_3dCoord(frontPos.x, frontPos.y, frontPos.z + 3.0, false)
        if fzFound then frontPos = vector3(frontPos.x, frontPos.y, fz) end
        local szFound, sz = GetGroundZFor_3dCoord(sidePos.x, sidePos.y, sidePos.z + 3.0, false)
        if szFound then sidePos = vector3(sidePos.x, sidePos.y, sz) end
        local faFound, faz = GetGroundZFor_3dCoord(fuelApproach.x, fuelApproach.y, fuelApproach.z + 3.0, false)
        if faFound then fuelApproach = vector3(fuelApproach.x, fuelApproach.y, faz) end
        local fnaFound, fnaz = GetGroundZFor_3dCoord(frontApproach.x, frontApproach.y, frontApproach.z + 3.0, false)
        if fnaFound then frontApproach = vector3(frontApproach.x, frontApproach.y, fnaz) end
        local saFound, saz = GetGroundZFor_3dCoord(sideApproach.x, sideApproach.y, sideApproach.z + 3.0, false)
        if saFound then sideApproach = vector3(sideApproach.x, sideApproach.y, saz) end
    end
    -- Role mapping (1=fuel, 2=hood mechanic, 3=tire/passenger side)
    local refuelPed = zoneData.crew[1]
    local hoodPed   = zoneData.crew[2]
    local jackPed   = zoneData.crew[3]

    -- Preload anim dictionaries and wait briefly to ensure availability
    local refuelDict = "timetable@gardener@filling_can"
    local mechDict   = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@"
    local bendDict   = "mini@repair" -- hood ped bending/working anim
    RequestAnimDict(refuelDict)
    RequestAnimDict(mechDict)
    RequestAnimDict(bendDict)
    local adDeadline = GetGameTimer() + 1500
    while (not HasAnimDictLoaded(refuelDict) or not HasAnimDictLoaded(mechDict) or not HasAnimDictLoaded(bendDict)) and GetGameTimer() < adDeadline do
        Wait(0)
    end

    -- DEBUG: where they’re going
    if Config.DebugPrints then print("[dps-roxwoodracing] REFUELER moving to →", fuelPos) end

    -- prepare peds for movement: unfreeze, allow tasks, keep tasks
    local function prep(p)
        FreezeEntityPosition(p, false)
        SetBlockingOfNonTemporaryEvents(p, false)
        ClearPedTasksImmediately(p)
        SetPedKeepTask(p, true)
        -- reduce weird climbing and collisions
        SetPedPathCanUseClimbovers(p, false)
        SetPedPathCanUseLadders(p, false)
        SetPedPathPreferToAvoidWater(p, true)
    end
    prep(refuelPed); prep(jackPed); prep(hoodPed)

    -- movement targets (with safe Z)
    local rfFound, rfz = GetGroundZFor_3dCoord(fuelPos.x, fuelPos.y, fuelPos.z + 3.0, false)
    local rfx, rfy, rfz2 = fuelPos.x, fuelPos.y, rfFound and rfz or fuelPos.z

    -- Get configurable timing values
    local timing = Config.PitStopTiming or {}
    local crewSpeed = timing.crewWalkSpeed or 2.0
    local approachTimeout = timing.approachTimeout or 8000

    -- staged movement
    TaskGoStraightToCoord(refuelPed, fuelApproach.x, fuelApproach.y, fuelApproach.z, crewSpeed, -1, GetEntityHeading(veh), 0.5)
    -- jack ped: route via a front gate then to passenger side to avoid cutting across the hood
    local frontGate = GetOffsetFromEntityInWorldCoords(veh, 0.0, 2.8, 0.0)
    local fgFound, fgz = GetGroundZFor_3dCoord(frontGate.x, frontGate.y, frontGate.z + 3.0, false)
    if fgFound then frontGate = vector3(frontGate.x, frontGate.y, fgz) end
    TaskGoStraightToCoord(jackPed,   frontGate.x,  frontGate.y,  frontGate.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5)
    -- hood ped: approach front center of the vehicle
    TaskGoStraightToCoord(hoodPed,   frontApproach.x, frontApproach.y, frontApproach.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5)

    if Config.DebugPrints then
        print(string.format("[dps-roxwoodracing] Move orders → refuel:(%.2f,%.2f,%.2f) hood:(%.2f,%.2f,%.2f) tire:(%.2f,%.2f,%.2f)",
            rfx,rfy,rfz2, frontPos.x,frontPos.y,frontPos.z, sidePos.x,sidePos.y,sidePos.z))
    end

    Wait(1000)

    -- REFUEL: load jerry can model, attach & anim
    RequestModel(canModel)
    local canDeadline = GetGameTimer() + 5000
    while not HasModelLoaded(canModel) and GetGameTimer() < canDeadline do Wait(0) end
    local canObj = CreateObject(canModel, fuelPos.x, fuelPos.y, fuelPos.z, true, true, false)
    -- Attach to a stable right-hand prop bone with neutral transform to avoid face-clipping
    -- If this looks off in your model pack, we can tweak offsets/rotations slightly.
    AttachEntityToEntity(
        canObj,
        refuelPed,
        GetPedBoneIndex(refuelPed, 60309), -- left-hand prop bone (PH_L_Hand)
        -0.02, -0.03, 0.32,               -- raise more so hand lines up with top handle
        180.0, 0.0, 0.0,                   -- flipped top-to-bottom
        true, true, false, true, 1, true
    )
    -- wait for peds to reach targets (simple distance checks)
    local function waitNear(ped, tgt, dist, timeout)
        local t0 = GetGameTimer()
        while #(GetEntityCoords(ped) - tgt) > (dist or 1.0) and (GetGameTimer() - t0) < (timeout or 4000) do
            Wait(100)
        end
    end
    -- wait for approach phase (refuel to fuelApproach, jack to frontGate then sideApproach)
    local t0 = GetGameTimer()
    local atRefuelA, atHoodA, atJackA = false, false, false
    local jackAtGate = false
    while (GetGameTimer() - t0) < approachTimeout do
        if not atRefuelA and #(GetEntityCoords(refuelPed) - fuelApproach) <= 1.6 then atRefuelA = true end
        if not atHoodA   and #(GetEntityCoords(hoodPed)   - frontApproach) <= 1.6 then atHoodA = true end
        if (not jackAtGate) and #(GetEntityCoords(jackPed) - frontGate) <= 1.6 then
            jackAtGate = true
            TaskGoStraightToCoord(jackPed,   sideApproach.x,  sideApproach.y,  sideApproach.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5)
        end
        if not atJackA and #(GetEntityCoords(jackPed) - sideApproach) <= 1.6 then atJackA = true end
        if atRefuelA and atHoodA and atJackA then break end
        -- nudge if stuck
        if (GetGameTimer() - t0) % 1200 < 60 then
            if not atRefuelA then TaskGoStraightToCoord(refuelPed, fuelApproach.x, fuelApproach.y, fuelApproach.z, crewSpeed, -1, GetEntityHeading(veh), 0.5) end
            if not atHoodA   then TaskGoStraightToCoord(hoodPed,   frontApproach.x, frontApproach.y, frontApproach.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5) end
            if not atJackA then
                if jackAtGate then
                    TaskGoStraightToCoord(jackPed,   sideApproach.x,  sideApproach.y,  sideApproach.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5)
                else
                    TaskGoStraightToCoord(jackPed,   frontGate.x,  frontGate.y,  frontGate.z,  crewSpeed, -1, GetEntityHeading(veh), 0.5)
                end
            end
        end
        Wait(100)
    end
    -- final legs (slightly slower for precision positioning)
    local finalSpeed = math.max(1.5, crewSpeed - 0.5)
    TaskGoStraightToCoord(refuelPed, rfx, rfy, rfz2, finalSpeed, -1, GetEntityHeading(veh), 0.5)
    TaskGoStraightToCoord(jackPed,   sidePos.x,  sidePos.y,  sidePos.z,  finalSpeed, -1, GetEntityHeading(veh), 0.5)
    TaskGoStraightToCoord(hoodPed,   frontPos.x, frontPos.y, frontPos.z, finalSpeed, -1, GetEntityHeading(veh), 0.5)

    local t1 = GetGameTimer()
    local arrivedRefuel, arrivedHood, arrivedJack = false, false, false
    while (GetGameTimer() - t1) < 6000 do
        if not arrivedRefuel and #(GetEntityCoords(refuelPed) - vector3(rfx, rfy, rfz2)) <= 1.4 then arrivedRefuel = true end
        if not arrivedHood   and #(GetEntityCoords(hoodPed)   - frontPos) <= 1.4 then arrivedHood = true end
        if not arrivedJack   and #(GetEntityCoords(jackPed)   - sidePos)  <= 1.4 then arrivedJack = true end
        if arrivedRefuel and arrivedHood and arrivedJack then break end
        if (GetGameTimer() - t1) % 1500 < 60 then
            if not arrivedRefuel then TaskGoStraightToCoord(refuelPed, rfx, rfy, rfz2, 2.2, -1, GetEntityHeading(veh), 0.5) end
            if not arrivedHood   then TaskGoStraightToCoord(hoodPed,   frontPos.x, frontPos.y, frontPos.z, 2.2, -1, GetEntityHeading(veh), 0.5) end
            if not arrivedJack   then TaskGoStraightToCoord(jackPed,   sidePos.x,  sidePos.y,  sidePos.z,  2.2, -1, GetEntityHeading(veh), 0.5) end
        end
        Wait(100)
    end

    -- Last-mile correction: if anyone hasn't reached, snap to final spot
    if not arrivedHood then SetEntityCoords(hoodPed, frontPos.x, frontPos.y, frontPos.z, false, false, false, true) end
    if not arrivedJack then SetEntityCoords(jackPed, sidePos.x, sidePos.y, sidePos.z, false, false, false, true) end

    -- Hood ped: lock at engine bay, face the car, and play bending work loop
    SetPedKeepTask(hoodPed, false)
    ClearPedTasksImmediately(hoodPed)
    SetEntityCoords(hoodPed, frontPos.x, frontPos.y, frontPos.z, false, false, false, true)
    local hoodFaceHeading = (GetEntityHeading(veh) + 180.0) % 360.0
    SetEntityHeading(hoodPed, hoodFaceHeading)
    SetEntityCollision(hoodPed, false, false)
    FreezeEntityPosition(hoodPed, true)
    -- open hood while working
    SetVehicleDoorOpen(veh, 4, false, false)
    TaskPlayAnim(hoodPed, "mini@repair", "fixing_a_ped", 8.0, -8.0, -1, 1, 0.0, false, false, false)

    -- Lock jack ped at wheel location to prevent climbing before anim
    SetPedKeepTask(jackPed, false)
    ClearPedTasksImmediately(jackPed)
    SetEntityCoords(jackPed, sidePos.x, sidePos.y, sidePos.z, false, false, false, true)
    -- face the car from the passenger side (90° inward relative to vehicle heading)
    local faceHeading = (GetEntityHeading(veh) + 90.0) % 360.0
    SetEntityHeading(jackPed, faceHeading)
    -- avoid collision pushes from the vehicle while animating
    SetEntityCollision(jackPed, false, false)
    FreezeEntityPosition(jackPed, true)

    -- Immediately start assigned animations on arrival
    -- 1) Refuel ped: snap, face vehicle (driver side inward), freeze, and play filling animation
    SetPedKeepTask(refuelPed, false)
    ClearPedTasksImmediately(refuelPed)
    SetEntityCoords(refuelPed, rfx, rfy, rfz2, false, false, false, true)
    -- set heading 90° to the RIGHT of vehicle forward (driver side faces inward)
    local refuelHeading = (GetEntityHeading(veh) - 90.0) % 360.0
    SetEntityHeading(refuelPed, refuelHeading)
    FreezeEntityPosition(refuelPed, true)
    -- play animations (dicts requested earlier)
    TaskPlayAnim(refuelPed, "timetable@gardener@filling_can", "gar_ig_5_filling_can", 8.0, -8.0, -1, 49, 0.0, false, false, false)

    -- 2) Jack/tire ped: play mechanic loop at wheel
    TaskPlayAnim(jackPed, "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer", 8.0, -8.0, -1, 1, 0.0, false, false, false)

    -- fill + repair (using configurable timing)
    local refuelSteps = timing.refuelSteps or 15
    local refuelStepMs = timing.refuelStepMs or 200
    local startFuel = math.max(0.0, GetVehicleFuelLevel(veh))
    for i = 1, refuelSteps do
        local lvl = startFuel + (100 - startFuel) * (i / refuelSteps)
        Fuel.Set(veh, lvl)
        Wait(refuelStepMs)
    end
    -- ensure final sync across fuel scripts
    Fuel.SetFull(veh)
    -- verify and immediately re-assert 100% if any script lags a tick updating its own store (e.g., LegacyFuel)
    Wait(200)
    local readBack = GetVehicleFuelLevel(veh)
    if readBack < 99.0 then
        Fuel.SetFull(veh)
        local nid = NetworkGetNetworkIdFromEntity(veh)
        if nid and nid ~= 0 then TriggerServerEvent('dps-roxwoodracing:server:setFuel', nid, 100.0) end
    end
    -- short client-side watchdog specifically for LegacyFuel to prevent late cache restores
    CreateThread(function()
        if GetResourceState('LegacyFuel') ~= 'started' then return end
        local tries = 0
        while tries < 6 do
            tries = tries + 1
            if DoesEntityExist(veh) then
                -- Native + LegacyFuel export
                SetVehicleFuelLevel(veh, 100.0)
                pcall(function() exports['LegacyFuel']:SetFuel(veh, 100) end)
            end
            Wait(250)
        end
    end)
    SetVehicleDeformationFixed(veh)
    SetVehicleFixed(veh)
    -- close hood after "work" period
    SetVehicleDoorShut(veh, 4, false)

    -- cleanup
    ClearPedTasks(refuelPed)
    DeleteEntity(canObj)
    SetModelAsNoLongerNeeded(canModel)
    RemoveAnimDict("timetable@gardener@filling_can")
    RemoveAnimDict("anim@amb@clubhouse@tutorial@bkr_tut_ig3@")
    RemoveAnimDict("mini@repair")
    ClearPedTasks(hoodPed)
    ClearPedTasks(jackPed)

    -- return crew (snap targets to ground and check horizontal distance for precision)
    local returnTargets = {}        -- indexed by ped handle to avoid any index mismatch
    for i, cp in ipairs(zoneData.crew) do
        ClearPedTasks(cp)
        local off = zoneData.crewIdle[i]
        FreezeEntityPosition(cp, false)
        SetEntityCollision(cp, true, true)

        -- Prefer the exact spawn home for this ped to avoid index mixups
        local home = zoneData.crewHome and zoneData.crewHome[cp]
        local tx, ty, tz
        if home then
            tx, ty, tz = home.x, home.y, home.z
        else
            tx = baseCoords.x + off.x
            ty = baseCoords.y + off.y
            tz = baseCoords.z + off.z
        end
        local foundGZ, gz = GetGroundZFor_3dCoord(tx, ty, tz + 3.0, false)
        if foundGZ then tz = gz end
        returnTargets[cp] = vector3(tx, ty, tz)

        TaskGoToCoordAnyMeans(cp, tx, ty, tz, 2.0, 0, 0, 786603, 0.0)
    end
    local returnTimeout = timing.returnTimeout or 15000
    local backStart = GetGameTimer()
    repeat
        Wait(50)
        local allBack = true
        for i, cp in ipairs(zoneData.crew) do
            local tgt = returnTargets[cp]
            local p = GetEntityCoords(cp)
            local dx, dy = (p.x - tgt.x), (p.y - tgt.y)
            local dist2d = math.sqrt(dx*dx + dy*dy)
            if dist2d > 1.1 then allBack = false; break end
        end
        if allBack or (GetGameTimer() - backStart) > returnTimeout then break end
    until false
    -- Freeze, snap to exact home, face original spawn heading, and resume idle scenario
    local retHeading = zoneData.spawnHeading or (zoneCfg.heading or 0.0)
    local idleAnims = Config.PitCrewIdleAnims or { "WORLD_HUMAN_STAND_IMPATIENT" }
    for _, cp in ipairs(zoneData.crew) do
        local tgt = returnTargets[cp]
        if tgt then
            SetEntityCoords(cp, tgt.x, tgt.y, tgt.z, false, false, false, true)
        end
        FreezeEntityPosition(cp, true)
        SetEntityHeading(cp, retHeading)
        ClearPedTasksImmediately(cp)
        -- Random idle animation for variety
        local randomAnim = idleAnims[math.random(1, #idleAnims)]
        TaskStartScenarioInPlace(cp, randomAnim, 0, true)
    end

    -- unfreeze & toast (robust release)
    local function ensureVehicleReleased(entity)
        -- gain control
        if not NetworkHasControlOfEntity(entity) then
            NetworkRequestControlOfEntity(entity)
            local t0 = GetGameTimer()
            while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - t0) < 750 do Wait(0) end
        end
        SetVehicleUndriveable(entity, false)
        SetEntityCollision(entity, true, true)
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        FreezeEntityPosition(entity, false)
        for _ = 1, 4 do
            Wait(120)
            if IsEntityPositionFrozen(entity) then FreezeEntityPosition(entity, false) end
        end
    end
    ensureVehicleReleased(veh)
    -- final belt-and-suspenders: re-assert full after release in case a late consumer tick runs
    CreateThread(function()
        Wait(400)
        local lvl = GetVehicleFuelLevel(veh)
        if lvl < 99.0 then
            Fuel.SetFull(veh)
            local nid = NetworkGetNetworkIdFromEntity(veh)
            if nid and nid ~= 0 then TriggerServerEvent('dps-roxwoodracing:server:setFuel', nid, 100.0) end
        end
    end)
    AddTextEntry("PIT_RETURN", "Return to Race")
    BeginTextCommandPrint("PIT_RETURN")
    EndTextCommandPrint(3000, true)
end

--------------------------------------------------------------------------------
-- 3) PIT DETECTION: one lib.zones sphere per box, armed only during a race
--------------------------------------------------------------------------------
Pit = { zones = {}, armed = false }
local waiting = nil

local function watchForStop(idx)
  -- Runs only while the racer is inside pit box idx and has not yet stopped.
  if waiting then return end
  waiting = idx
  CreateThread(function()
    while waiting == idx and IsRaceActive() do
      local veh = GetVehiclePedIsIn(PlayerPedId(), false)
      if veh ~= 0 and not inPit and GetEntitySpeed(veh) < 0.5 and GetGameTimer() > pitCooldownUntil then
        inPit = true
        RunPitStop(veh, idx)
        break
      end
      Wait(250)
    end
    if waiting == idx then waiting = nil end
  end)
end

function Pit.Arm()
  if Pit.armed then return end
  Pit.armed = true
  for idx, zone in ipairs(Config.PitCrewZones) do
    Pit.zones[idx] = lib.zones.sphere({
      coords = zone.coords, radius = zone.radius, debug = Config.ZoneDebug,
      onEnter = function() if IsRaceActive() then watchForStop(idx) end end,
      onExit = function()
        if waiting == idx then waiting = nil end
        if inPit then
          local veh = GetVehiclePedIsIn(PlayerPedId(), false)
          if veh ~= 0 then FreezeEntityPosition(veh, false) end
          inPit = false
          pitCooldownUntil = GetGameTimer() + 10000
        end
      end,
    })
    -- Marker: per-frame only while within 60 m of this box
    Pit.zones['pt' .. idx] = lib.points.new({ coords = zone.coords, distance = 60.0, nearby = function()
      local size = (zone.radius * 2.0) / 6.0
      DrawMarker(36, zone.coords.x, zone.coords.y, zone.coords.z + 1.0, 0, 0, 0, 0, 0, 0, size, size, size, 255, 255, 255, 200, false, true, 2, false, nil, nil, false)
    end })
  end
end

function Pit.Disarm()
  for k, z in pairs(Pit.zones) do pcall(function() z:remove() end); Pit.zones[k] = nil end
  Pit.armed = false; waiting = nil; inPit = false
end
