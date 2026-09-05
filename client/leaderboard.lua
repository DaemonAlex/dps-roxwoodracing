-- cl_leaderboard.lua
-- Adapted from glitchdetector's amir-leaderboard (cl_speedway.lua)
-- Renders an in-world LED scoreboard at Roxwood Speedway using DUI

if not Config.Leaderboard or not Config.Leaderboard.enabled then return end

local DuiObject = nil

local function EnsureModel(model)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
end

CreateThread(function()
    print("[dps-roxwoodracing] Loading leaderboard sign...")
    EnsureModel("amir_speedway_led")
    DuiObject = CreateDui("nui://dps-roxwoodracing/html/led.html", 512, 512)
    local timeout = GetNetworkTime()
    while not IsDuiAvailable(DuiObject) and GetNetworkTime() - timeout < 6000 do
        Wait(0)
    end
    print("[dps-roxwoodracing] Leaderboard sign loaded!")
    local txd = CreateRuntimeTxd('amir_speedway_sign')
    local dui = GetDuiHandle(DuiObject)
    CreateRuntimeTextureFromDuiHandle(txd, "amir_speedway_led", dui)
    AddReplaceTexture('amir_speedway_led', 'amir_speedway_led', 'amir_speedway_sign', "amir_speedway_led")
    SetModelAsNoLongerNeeded("amir_speedway_led")

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
end)

-- Clean up DUI on resource stop to prevent orphaned objects on restart
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if DuiObject then
        DestroyDui(DuiObject)
        DuiObject = nil
    end
end)
