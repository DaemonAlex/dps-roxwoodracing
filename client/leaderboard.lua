-- cl_leaderboard.lua
-- Adapted from glitchdetector's amir-leaderboard (cl_speedway.lua)
-- Renders an in-world LED scoreboard at Roxwood Speedway using DUI

if not Config.Leaderboard or not Config.Leaderboard.enabled then return end

local DuiObject = nil
local SIGN_MODEL = "amir_speedway_led"   -- archetype from stream/def_amir_speedway.ytyp
local SIGN_TXD   = "amir_speedway_led"   -- texture dictionary + texture name inside the .ytd
local RUNTIME_TXD = "amir_speedway_sign"
local replacementApplied = false

local function log(msg) print("[dps-roxwoodracing] sign: " .. msg) end

-- Load the sign archetype so its texture dictionary is resident when the replacement is
-- registered. Bounded wait: a missing archetype must not hang this thread forever.
local function EnsureModel(model, timeoutMs)
    local hash = joaat(model)
    if not IsModelValid(hash) then
        log(("model '%s' is not valid on this client (ytyp not registered?)"):format(model))
        return false
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(50) end
    if not HasModelLoaded(hash) then
        log(("model '%s' did not load within %d ms"):format(model, timeoutMs or 10000))
        return false
    end
    return true
end

-- Point the sign's texture at the DUI. Safe to call more than once.
local function ApplyReplacement(reason)
    if not DuiObject then return end
    local loaded = EnsureModel(SIGN_MODEL, 10000)
    AddReplaceTexture(SIGN_TXD, SIGN_TXD, RUNTIME_TXD, SIGN_TXD)
    SetModelAsNoLongerNeeded(joaat(SIGN_MODEL))
    replacementApplied = true
    log(("texture replacement applied (%s, model loaded=%s)"):format(reason, tostring(loaded)))
end

CreateThread(function()
    log("loading leaderboard sign...")
    DuiObject = CreateDui("nui://dps-roxwoodracing/html/led.html", 512, 512)
    local deadline = GetGameTimer() + 10000
    while not IsDuiAvailable(DuiObject) and GetGameTimer() < deadline do Wait(50) end
    if not IsDuiAvailable(DuiObject) then
        log("DUI page not available after 10 s; the board will stay on its baked texture")
    end
    local txd = CreateRuntimeTxd(RUNTIME_TXD)
    local dui = GetDuiHandle(DuiObject)
    CreateRuntimeTextureFromDuiHandle(txd, SIGN_TXD, dui)
    ApplyReplacement("startup")

    RegisterNetEvent("dps-roxwoodracing:setPlayerTimes", function(title, players)
        SendDuiMessage(DuiObject, json.encode({
            type = "playerTimes",
            title = title,
            players = players
        }))
    end)

    RegisterNetEvent("dps-roxwoodracing:setPlayerNames", function(title, players)
        SendDuiMessage(DuiObject, json.encode({
            type = "playerNames",
            title = title,
            players = players
        }))
    end)

    RegisterNetEvent("dps-roxwoodracing:setText", function(title, players)
        SendDuiMessage(DuiObject, json.encode({
            type = "playerText",
            title = title,
            players = players
        }))
    end)

    RegisterNetEvent("dps-roxwoodracing:setAdUrls", function(urls)
        SendDuiMessage(DuiObject, json.encode({
            type = "ads",
            url = urls,
        }))
    end)

    -- Request current display state from the server so late-joiners see the board
    TriggerServerEvent("dps-roxwoodracing:requestData")

    -- Re-apply when a player gets near the sign. If the dictionary was not resident at
    -- startup (Roxwood is far from most spawns) the first registration can miss; this one
    -- runs with the sign streamed in. One-shot per approach, no polling of our own.
    if Config.Leaderboard.signCoords then
        lib.points.new({
            coords = Config.Leaderboard.signCoords,
            distance = Config.Leaderboard.signRadius or 300.0,
            onEnter = function()
                CreateThread(function() ApplyReplacement("near sign") end)
            end,
        })
    end
end)

-- Clean up DUI on resource stop to prevent orphaned objects on restart
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if DuiObject then
        DestroyDui(DuiObject)
        DuiObject = nil
    end
end)
