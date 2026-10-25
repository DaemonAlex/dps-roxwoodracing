-- Track boost (Damon 2026-10-12): a race car (registry category race_*) gets more power
-- and grip while it is on a track, and goes back to exactly what it had when it leaves
-- the track or the driver gets out. The "on a track" zones are made in practice.lua
-- (armTracks) around each track's racing line and announced with the
-- dps-roxwoodracing:trackboost event. Settings: Config.Practice.trackBoost.
-- Balance of performance (Damon 2026-10-25): a car listed in one of this track's grid sets
-- is set to that class's target here instead (Config.Practice.balance), the same target the
-- AI in that class runs, so players and AI in a class race on equal cars.

local cfg = Config.Practice and Config.Practice.trackBoost
if not cfg or cfg.enabled == false then return end
local balance = Config.Practice.balance
local ai = Config.Practice.ai or {}

local onTrack = nil   -- id of the track this player is on, nil off track
local boosted = {}    -- vehicle handle -> { fields = handling values before, capped = true when a ceiling was set }

local FIELDS = {
    fInitialDriveForce = 'power',
    fTractionCurveMax  = 'grip',
    fTractionCurveMin  = 'grip',
}

local function registryEntry(veh)
    local entry = exports.qbx_core:GetVehiclesByHash(GetEntityModel(veh))
    -- GetVehiclesByHash returns the whole table when the hash is unknown; that has no model
    if type(entry) == 'table' and type(entry.model) == 'string' then return entry end
    return nil
end

local function isRaceCar(veh)
    local entry = registryEntry(veh)
    local cat = entry and entry.category
    return type(cat) == 'string' and cat:sub(1, 5) == 'race_'
end

-- The class this car races in on this track and the class's target there, or nil.
local function classTarget(veh, trackId)
    if not balance or balance.enabled == false or not trackId then return nil end
    local entry = registryEntry(veh)
    if not entry then return nil end
    local per = ai.perTrack and ai.perTrack[trackId]
    local label = Practice.ClassOf((per and per.sets) or ai.sets, entry.model)
    local target = Practice.BalanceTarget(balance.classes, balance.tracks and balance.tracks[trackId], label)
    return target and label, target
end

local function restore(veh)
    local orig = boosted[veh]
    boosted[veh] = nil
    if not orig or not DoesEntityExist(veh) then return end
    for field, value in pairs(orig.fields) do
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value)
    end
    if orig.capped then SetEntityMaxSpeed(veh, 1000.0) end   -- lift the class ceiling
    if cfg.notify then lib.notify({ description = orig.label and 'Balance off' or 'Track boost off', type = 'inform', duration = 2500 }) end
end

local function apply(veh, label, target)
    local orig = { fields = {}, label = label }
    for field in pairs(FIELDS) do
        orig.fields[field] = GetVehicleHandlingFloat(veh, 'CHandlingData', field)
    end
    local f = orig.fields
    if target then
        -- Balanced: the class's grip, power and top-speed ceiling on this track
        local b = Practice.Balance(target, { traction = f.fTractionCurveMax, drive = f.fInitialDriveForce })
        if b.grip and f.fTractionCurveMax > 0 then
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', b.grip)
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin', f.fTractionCurveMin * b.grip / f.fTractionCurveMax)
        end
        if b.power then SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', b.power) end
        if b.top then SetEntityMaxSpeed(veh, b.top); orig.capped = true end
    else
        for field, kind in pairs(FIELDS) do
            SetVehicleHandlingFloat(veh, 'CHandlingData', field, f[field] * (cfg[kind] or 1.0))
        end
    end
    boosted[veh] = orig
    if cfg.notify and target and balance.notify ~= false then
        lib.notify({ description = ('Balanced to %s for this track'):format(label), type = 'success', duration = 3000 })
    elseif cfg.notify and not target then
        lib.notify({ description = 'Track boost on', type = 'success', duration = 2500 })
    end
end

-- Boost the car the player is driving when on a track; undo it everywhere else.
local function refresh(current)
    local veh = current
    if veh == nil then veh = cache.vehicle end
    local driving = veh and veh ~= 0 and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == cache.ped
    for v in pairs(boosted) do
        if not onTrack or v ~= veh or not driving then restore(v) end
    end
    if onTrack and driving and not boosted[veh] then
        local label, target = classTarget(veh, onTrack)
        if target then apply(veh, label, target) elseif isRaceCar(veh) then apply(veh) end
    end
end

AddEventHandler('dps-roxwoodracing:trackboost', function(trackId, inside)
    if inside then
        onTrack = trackId
    elseif onTrack == trackId then
        onTrack = nil
    end
    refresh()
end)

-- cache.vehicle / cache.seat are updated after these callbacks, so pass the new value on
lib.onCache('vehicle', function(value) refresh(value or false) end)
lib.onCache('seat', function() SetTimeout(0, function() refresh() end) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for v in pairs(boosted) do restore(v) end
end)
