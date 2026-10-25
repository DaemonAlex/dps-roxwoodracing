-- Track boost (Damon 2026-10-12): a race car (registry category race_*) gets more power
-- and grip while it is on a track, and goes back to exactly what it had when it leaves
-- the track or the driver gets out. The "on a track" zones are made in practice.lua
-- (armTracks) around each track's racing line and announced with the
-- dps-roxwoodracing:trackboost event. Settings: Config.Practice.trackBoost.

local cfg = Config.Practice and Config.Practice.trackBoost
if not cfg or cfg.enabled == false then return end

local onTrack = nil   -- id of the track this player is on, nil off track
local boosted = {}    -- vehicle handle -> the handling values it had before the boost

local FIELDS = {
    fInitialDriveForce = 'power',
    fTractionCurveMax  = 'grip',
    fTractionCurveMin  = 'grip',
}

local function isRaceCar(veh)
    local entry = exports.qbx_core:GetVehiclesByHash(GetEntityModel(veh))
    -- GetVehiclesByHash returns the whole table when the hash is unknown; that has no category
    local cat = type(entry) == 'table' and entry.category
    return type(cat) == 'string' and cat:sub(1, 5) == 'race_'
end

local function restore(veh)
    local orig = boosted[veh]
    boosted[veh] = nil
    if not orig or not DoesEntityExist(veh) then return end
    for field, value in pairs(orig) do
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value)
    end
    if cfg.notify then lib.notify({ description = 'Track boost off', type = 'inform', duration = 2500 }) end
end

local function apply(veh)
    local orig = {}
    for field, kind in pairs(FIELDS) do
        local value = GetVehicleHandlingFloat(veh, 'CHandlingData', field)
        orig[field] = value
        SetVehicleHandlingFloat(veh, 'CHandlingData', field, value * (cfg[kind] or 1.0))
    end
    boosted[veh] = orig
    if cfg.notify then lib.notify({ description = 'Track boost on', type = 'success', duration = 2500 }) end
end

-- Boost the car the player is driving when on a track; undo it everywhere else.
local function refresh(current)
    local veh = current
    if veh == nil then veh = cache.vehicle end
    local driving = veh and veh ~= 0 and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == cache.ped
    for v in pairs(boosted) do
        if not onTrack or v ~= veh or not driving then restore(v) end
    end
    if onTrack and driving and not boosted[veh] and isRaceCar(veh) then apply(veh) end
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
