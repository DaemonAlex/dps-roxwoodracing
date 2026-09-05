-- sv_leaderboard.lua
-- Adapted from glitchdetector's amir-leaderboard (sv_speedway.lua)
-- Server-side display state management + idle best-times display

-- Config is a shared global

if not Config.Leaderboard or not Config.Leaderboard.enabled then return end

--------------------------------------------------------------------------------
-- Current display state (persisted for late-joining clients)
--------------------------------------------------------------------------------
local CurrentDisplayType = "setText"
local CurrentDisplayTitle = ""
local CurrentDisplayLines = {}
local CurrentDisplayAdUrls = { "ads/ad_2.png", "ads/ad_3.png", "ads/ad_4.png" }

--------------------------------------------------------------------------------
-- Core display functions (same API as original amir-leaderboard)
--------------------------------------------------------------------------------
local function showPlayerTimes(title, times)
    CurrentDisplayType = "setPlayerTimes"
    CurrentDisplayLines = times
    CurrentDisplayTitle = title
    TriggerClientEvent("dps-roxwoodracing:setPlayerTimes", -1, title, times)
end
AddEventHandler("amir-leaderboard:setPlayerTimes", showPlayerTimes)

local function showPlayerNames(title, names)
    CurrentDisplayType = "setPlayerNames"
    CurrentDisplayLines = names
    CurrentDisplayTitle = title
    TriggerClientEvent("dps-roxwoodracing:setPlayerNames", -1, title, names)
end
AddEventHandler("amir-leaderboard:setPlayerNames", showPlayerNames)

local function showText(title, lines)
    CurrentDisplayType = "setText"
    CurrentDisplayLines = lines
    CurrentDisplayTitle = title
    TriggerClientEvent("dps-roxwoodracing:setText", -1, title, lines)
end
AddEventHandler("amir-leaderboard:setText", showText)

local function setAdUrls(ad1, ad2, ad3)
    CurrentDisplayAdUrls = { ad1, ad2, ad3 }
    TriggerClientEvent("dps-roxwoodracing:setAdUrls", -1, CurrentDisplayAdUrls)
end
AddEventHandler("amir-leaderboard:setAdUrls", setAdUrls)

--------------------------------------------------------------------------------
-- Late-join data push
--------------------------------------------------------------------------------
RegisterServerEvent("dps-roxwoodracing:requestData")
AddEventHandler("dps-roxwoodracing:requestData", function()
    local src = source
    TriggerClientEvent("dps-roxwoodracing:" .. CurrentDisplayType, src, CurrentDisplayTitle, CurrentDisplayLines)
    TriggerClientEvent("dps-roxwoodracing:setAdUrls", src, CurrentDisplayAdUrls)
end)

--------------------------------------------------------------------------------
-- Idle best-times display
--------------------------------------------------------------------------------
local idleRunning = false
local idleStopFlag = false

--- Gather top 9 best lap times from all players across all tracks.
--- Returns { names = {string...}, times = {number...} } sorted by time ascending.
local function GetTopBestTimes()
    local rows = MySQL.query.await(('SELECT citizenid, best_laps FROM %s WHERE best_laps IS NOT NULL AND best_laps != ?'):format(Stats.TABLE), { '{}' })
    if not rows or #rows == 0 then return nil end

    local entries = {}

    for _, row in ipairs(rows) do
        local laps = json.decode(row.best_laps or '{}') or {}
        for track, time in pairs(laps) do
            if type(time) == 'number' and time > 0 then
                table.insert(entries, {
                    citizenid = row.citizenid,
                    track = track,
                    time = time,
                })
            end
        end
    end

    if #entries == 0 then return nil end

    table.sort(entries, function(a, b) return a.time < b.time end)

    -- Take top 9
    local top = {}
    for i = 1, math.min(9, #entries) do
        top[i] = entries[i]
    end

    -- Look up character names from the DB (cached per citizenid)
    local nameCache = {}
    local names, times = {}, {}
    for i, entry in ipairs(top) do
        if not nameCache[entry.citizenid] then
            nameCache[entry.citizenid] = Bridge.GetPlayerNameFromDB(entry.citizenid) or entry.citizenid:sub(1, 8)
        end
        names[i] = nameCache[entry.citizenid]
        times[i] = entry.time
    end

    -- Pad to 9 entries
    for i = #names + 1, 9 do
        names[i] = ""
        times[i] = 0
    end

    return { names = names, times = times }
end

--- Show the idle best-times leaderboard.
--- Toggles between names and times views until StopIdleLeaderboard() is called.
local function ShowIdleLeaderboard()
    if not Config.Leaderboard or not Config.Leaderboard.enabled then return end
    if not Config.Leaderboard.idleDisplay then return end
    if idleRunning then return end
    idleRunning = true
    idleStopFlag = false
    CreateThread(function()
        Wait(2000)
        if idleStopFlag then idleRunning = false return end
        local data = GetTopBestTimes()
        if not data then
            showText('BEST', { 'R', 'O', 'X', 'W', 'O', 'O', 'D', '', '' })
        else
            -- One push of names, one of times; the board is re-pushed only when a record changes.
            showPlayerNames('BEST', data.names)
        end
        idleRunning = false
    end)
end

-- A new track record was saved: refresh the idle board once (no race running)
AddEventHandler('dps-roxwoodracing:recordSet', function()
    if not idleStopFlag and not idleRunning then ShowIdleLeaderboard() end
end)

--- Stop the idle leaderboard display loop.
local function StopIdleLeaderboard()
    idleStopFlag = true
end

-- Exports so s_main.lua can call these
exports("ShowIdleLeaderboard", ShowIdleLeaderboard)
exports("StopIdleLeaderboard", StopIdleLeaderboard)
