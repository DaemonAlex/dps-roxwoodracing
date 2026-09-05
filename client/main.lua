-- client/c_main.lua

-- Config is a shared global

--------------------------------------------------------------------------------
-- 2) FUEL MODULE (moved to client/c_fuel.lua)
--------------------------------------------------------------------------------
-- Fuel.SetFull(veh) is defined in integrations/fuel.lua

--------------------------------------------------------------------------------
-- 4) RACE STATE
--------------------------------------------------------------------------------
local hasLobby             = false
--------------------------------------------------------------------------------
-- NATIVE LOBBY WAITING LIST DISPLAY
local lobbyDisplayActive = false
local lobbyDisplayMembers = {}
local lobbyDisplayName = ""
local nuiReady = false
local lobbyNuiVisible = false   -- track if the NUI lobby panel is currently shown
local lobbyHintShown = false    -- avoid spamming the hint toast

function ShowLobbyDisplay(name, members)
    -- Prefer NUI lobby overlay
    local hostName = name:match("^([%w_]+)_%d+$") or name
    if Config.DebugPrints then
        print("[DEBUG] ShowLobbyDisplay called: hostName=" .. tostring(hostName) .. ", members=" .. table.concat(members, ", "))
    end
    -- Send to NUI (timeout.html handles showLobby)
    local meIsHost = (lobbyOwner == GetPlayerServerId(PlayerId()))
    if not nuiReady then
        -- Defer until UI reports ready to avoid 'no UI frame' warning
        CreateThread(function()
            local tries = 0
            while not nuiReady and tries < 200 do -- up to ~10s
                tries = tries + 1
                Wait(50)
            end
            if nuiReady then
                SendNUIMessage({ action = 'showLobby', lobbyName = hostName, hostName = hostName, members = members, meIsHost = meIsHost, keyLabel = (Config.InteractKeyLabel or 'Left Alt') })
            end
        end)
    else
        SendNUIMessage({ action = 'showLobby', lobbyName = hostName, hostName = hostName, members = members, meIsHost = meIsHost, keyLabel = (Config.InteractKeyLabel or 'Left Alt') })
    end
    -- Disable native draw to avoid double UI
    lobbyDisplayActive = false
    lobbyDisplayName = hostName
    lobbyDisplayMembers = members
    lobbyNuiVisible = true
    if not lobbyHintShown then
        lobbyHintShown = true
        if Notify then
            Notify(Locale("player_joined_title"), Locale("notify_interact_full", (Config.InteractKeyLabel or 'F2')), "inform", 7000)
        else
            print(("[dps-roxwoodracing] " .. Locale("hint_interact", (Config.InteractKeyLabel or 'F2'))))
        end
    end
end

function HideLobbyDisplay()
    lobbyDisplayActive = false
    if nuiReady then
        SendNUIMessage({ action = 'hideLobby' })
    end
    lobbyNuiVisible = false
    lobbyHintShown = false
end

-- Try to close any open input dialog
local function CloseVehicleSelectionUI()
    -- Close ox_lib input dialog if open
    pcall(function() lib.closeInputDialog() end)
    -- ensure focus is released as a last resort
    SetNuiFocus(false, false)
    -- reinforce focus off for a few frames in case another script re-asserts it
    CreateThread(function()
        for i=1,10 do
            SetNuiFocus(false, false)
            Wait(0)
        end
    end)
end

CreateThread(function()
    while true do
        Wait(0)
        if lobbyDisplayActive then
            -- Draw background (scaled down, moved further left)
            DrawRect(0.10, 0.5, 0.16, 0.09, 20, 20, 20, 200) -- x=0.10 (further left), y=0.5 (middle), width=0.16, height=0.09
            -- Draw title
            SetTextFont(4); SetTextScale(0.35,0.35); SetTextCentre(true)
            SetTextColour(255,255,255,255); SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString((Locale("lobby_word") .. ": " .. lobbyDisplayName))
            DrawText(0.10, 0.44)
            -- Draw member list
            for i, member in ipairs(lobbyDisplayMembers) do
                SetTextFont(0); SetTextScale(0.25,0.25); SetTextCentre(false)
                SetTextColour(255,255,255,255); SetTextOutline()
                SetTextEntry("STRING")
                local label = member .. (i == 1 and (" " .. Locale("host_tag")) or "")
                AddTextComponentString(label)
                DrawText(0.02, 0.47 + (i * 0.015))
            end
        end
    end
end)
-- NUI readiness handshake
RegisterNUICallback('nuiReady', function(_, cb)
    nuiReady = true
    -- send i18n pack to NUI
    SendNUIMessage({
        action = 'i18n',
        i18n = {
            speedwayTitle = Locale('speedway_title'),
            lobby         = Locale('lobby_word'),
            playerHeader  = Locale('player_header'),
            waiting       = Locale('waiting_for_players'),
            leave         = Locale('leave_lobby'),
            start         = Locale('start_race'),
            hostTag       = Locale('host_tag'),
            hintTemplate  = Locale('hint_interact', '{KEY}'),
            modalRemoved  = Locale('removed_modal_message'),
            modalDismiss  = Locale('dismiss'),
        }
    })
    if cb then cb({ ok = true }) end
end)

-- Toggle interact mode for the lobby tablet without permanently stealing input
local lobbyFocus = false
local function ToggleLobbyInteract()
    if not nuiReady then return end
    -- Only allow when the lobby overlay is visible
    -- Interact mode: capture NUI focus but DO NOT keep game input (prevents camera movement)
    lobbyFocus = not lobbyFocus
    if lobbyFocus then
        SetNuiFocusKeepInput(false)   -- do not pass mouse/keys to game while interacting
        SetNuiFocus(true, true)
    else
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
    SendNUIMessage({ action = 'lobbyFocus', on = lobbyFocus })
end

RegisterCommand('speedway_lobby_interact', function()
    -- Only allow interact toggle when lobby overlay is visible and we're not in race or a blocking modal
    if lobbyNuiVisible and not inRace and not timeoutModalActive then
        ToggleLobbyInteract()
    end
end, false)

-- Backup chat command if keybind isn't working; same gating rules
RegisterCommand('lobby', function()
    if lobbyNuiVisible and not inRace and not timeoutModalActive then
        ToggleLobbyInteract()
    else
    Notify(Locale("speedway_title"), Locale("lobby_controls_only_visible"), "error", 3500)
    end
end, false)
-- Default keybind: Left Alt (LMENU). Players can remap via FiveM key bindings.
RegisterKeyMapping('speedway_lobby_interact', Locale('keybind_interact_label'), 'keyboard', Config.InteractKey or 'F2')

-- Removed qb-target lobbyInteract event: interaction now uses F6 toggle only

-- NUI callbacks from the tablet buttons
RegisterNUICallback('lobbyStart', function(data, cb)
    if lobbyOwner ~= GetPlayerServerId(PlayerId()) then cb('not_host'); return end
    if currentLobby then TriggerServerEvent('dps-roxwoodracing:startRace', currentLobby) end
    -- Release focus after click
    lobbyFocus = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'lobbyFocus', on = false })
    HideLobbyDisplay()
    -- suppress auto-interact until Alt is released to avoid re-triggering instantly
    speedwaySuppressAutoUntilAltUp = true
    cb('ok')
end)

RegisterNUICallback('lobbyLeave', function(_, cb)
    if currentLobby then TriggerServerEvent('dps-roxwoodracing:leaveLobby', currentLobby) end
    lobbyFocus = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'lobbyFocus', on = false })
    -- suppress auto-interact until Alt is released to avoid re-triggering instantly
    speedwaySuppressAutoUntilAltUp = true
    cb('ok')
end)

-- ESC from lobby tablet: return to passive preview without taking any action
RegisterNUICallback('lobbyCancel', function(_, cb)
    lobbyFocus = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'lobbyFocus', on = false })
    -- suppress auto-interact until Alt is released to avoid re-triggering instantly
    speedwaySuppressAutoUntilAltUp = true
    cb('ok')
end)

-- Safety: cleanup on resource stop
AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    -- Reuse the same cleanup as server-triggered destroy
    TriggerEvent('dps-roxwoodracing:client:destroyprops')
end)
local currentProps         = {}
local currentZones         = {}
local racerCheckpointIndex = 0
local inRace               = false
local myPosition           = 0
local totalRacers          = 0
-- Expose race state for other client scripts (c_pit.lua)
function IsSpeedwayRaceActive() return inRace end

--------------------------------------------------------------------------------
-- GHOSTING STATE
--------------------------------------------------------------------------------
local raceNetIds  = {}   -- { {pid=, netId=}, ... } from server
local ghostActive = false
local myRaceVeh   = nil  -- entity handle of our race vehicle

local function StartGhostThread()
    ghostActive = true
    local ghostEntities = {}  -- cached entity handles for fast loop

    -- Fast loop: collision disable only (every frame for rock-solid no-clip)
    CreateThread(function()
        while ghostActive and inRace do
            if myRaceVeh and DoesEntityExist(myRaceVeh) then
                for _, ent in ipairs(ghostEntities) do
                    if DoesEntityExist(ent) then
                        SetEntityNoCollisionEntity(myRaceVeh, ent, true)
                    end
                end
            end
            Wait(0)
        end
    end)

    -- Slow loop: entity resolution + alpha (200ms throttle)
    CreateThread(function()
        while ghostActive and inRace do
            local resolved = {}
            for _, v in ipairs(raceNetIds) do
                local other = NetworkGetEntityFromNetworkId(v.netId)
                if DoesEntityExist(other) and other ~= myRaceVeh then
                    resolved[#resolved+1] = other
                    SetEntityAlpha(other, Config.Ghosting.ghostAlpha, false)
                end
            end
            ghostEntities = resolved  -- atomic swap for fast loop
            Wait(200)
        end
        -- Cleanup: restore alpha on all known race vehicles
        for _, v in ipairs(raceNetIds) do
            local other = NetworkGetEntityFromNetworkId(v.netId)
            if DoesEntityExist(other) then
                ResetEntityAlpha(other)
            end
        end
    end)
end

-- Receive all race vehicle netIds from server
RegisterNetEvent("dps-roxwoodracing:raceVehicles", function(vehicles)
    raceNetIds = vehicles or {}
end)

-- End start-of-race ghost period
RegisterNetEvent("dps-roxwoodracing:client:unghost", function()
    ghostActive = false
end)

-- Lapped-player ghost toggle (ghost self against all others)
RegisterNetEvent("dps-roxwoodracing:client:setGhosted", function(isGhosted)
    if isGhosted then
        StartGhostThread()
    else
        ghostActive = false
    end
end)

--------------------------------------------------------------------------------
-- 5) COMPUTE DISTANCE ALONG TRACK
--------------------------------------------------------------------------------
local function ComputeDistanceAlongTrack(pos)
    -- Monotonic distance since lap start using last passed checkpoint index (0..n)
    -- Includes virtual segment from Start/Finish -> CP1 (segIdx=0) and from last CP -> Start/Finish (segIdx=n)
    if not currentTrack then return 0 end
    local track = Config.Checkpoints[currentTrack]
    if not track or #track < 1 then return 0 end

    local function v3(v) return vector3(v.x, v.y, v.z) end
    local startNode = v3(Config.FinishLine.coords or Config.StartLinePoints[1])
    local n = #track

    -- helper to access the node list with virtual endpoints
    local function getNode(i)
        if i == 0 then return startNode end
        if i >= 1 and i <= n then return v3(track[i]) end
        if i == n + 1 then return startNode end
        -- clamp fallback
        if i < 0 then return startNode end
        return startNode
    end

    -- segment index equals last passed checkpoint; clamp to [0, n]
    local segIdx = racerCheckpointIndex or 0
    if segIdx < 0 then segIdx = 0 end
    if segIdx > n then segIdx = n end

    -- helper: build a polyline for a given big segment using optional hints
    local function buildSegmentNodes(seg)
        local nodes = {}
        local a = getNode(seg)
        local b = getNode(seg + 1)
        table.insert(nodes, a)
        local hintsByTrack = Config.SegmentHints and Config.SegmentHints[currentTrack]
        local hints = hintsByTrack and hintsByTrack[seg]
        -- Support configs that index the final segment (CPn->Finish) as (n-1)
        if (not hints) and seg == n and hintsByTrack then
            hints = hintsByTrack[n - 1]
        end
        if hints then
            for _, h in ipairs(hints) do
                table.insert(nodes, v3(h))
            end
        end
        table.insert(nodes, b)
        return nodes
    end

    -- sum of completed big segments since the Start/Finish line
    local total = 0.0
    for i = 0, segIdx - 1 do
        local nodes = buildSegmentNodes(i)
        for k = 1, #nodes - 1 do
            total = total + #(nodes[k+1] - nodes[k])
        end
    end

    -- progress along current big segment using closest point on polyline
    local nodes = buildSegmentNodes(segIdx)
    local segLen = 0.0
    local cumLen = 0.0
    local bestDist = 0.0
    local bestD2 = math.huge
    -- precompute sub-lengths
    local subLens = {}
    for k = 1, #nodes - 1 do
        subLens[k] = #(nodes[k+1] - nodes[k])
        segLen = segLen + subLens[k]
    end
    for k = 1, #nodes - 1 do
        local a = nodes[k]
        local b = nodes[k+1]
        local ab = b - a
        local abLen = subLens[k]
        if abLen > 0.001 then
            local ap = pos - a
            local t = (ap.x*ab.x + ap.y*ab.y + ap.z*ab.z) / (abLen * abLen)
            if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
            local proj = a + (ab * t)
            local dp = pos - proj
            local d2 = (dp.x*dp.x + dp.y*dp.y + dp.z*dp.z)
            if d2 < bestD2 then
                bestD2 = d2
                bestDist = cumLen + (t * abLen)
            end
        end
        cumLen = cumLen + abLen
    end
    total = total + bestDist

    -- Anti-plateau smoothing near segment end: softly blend a small look-ahead portion
    -- onto the next segment so distance continues to increase approaching any boundary.
    -- Start smoothing earlier on tight approaches so distance doesn't appear to stall
    local NEAR_END_T = 0.90        -- last 10% of segment
    local LOOKAHEAD_MAX = 35.0     -- cap look-ahead to 35m
    if segLen > 0.001 then
    local tAlong = segLen > 0 and (bestDist / segLen) or 0.0
        if tAlong > NEAR_END_T then
            -- look ahead onto the next big segment's first subsegment
            local nextNodes = buildSegmentNodes(math.min(segIdx + 1, n))
            if #nextNodes >= 2 then
                local nb = nextNodes[2] - nextNodes[1]
                local nbLen = #(nb)
                if nbLen > 0.001 then
                    local pFromEnd = pos - nextNodes[1]
                    local t2 = (pFromEnd.x*nb.x + pFromEnd.y*nb.y + pFromEnd.z*nb.z) / (nbLen * nbLen)
                    if t2 > 0.0 then
                        local extra = t2 * nbLen
                        if extra < 0.0 then extra = 0.0 end
                        if extra > LOOKAHEAD_MAX then extra = LOOKAHEAD_MAX end
                        local blend = (tAlong - NEAR_END_T) / (1.0 - NEAR_END_T)
                        if blend < 0.0 then blend = 0.0 elseif blend > 1.0 then blend = 1.0 end
                        total = total + (blend * extra)
                    end
                end
            end
        end
    end

    return total
end

-- Helper: world position of the vehicle's front bumper, for better pass-by accuracy
local function GetVehicleFrontWorldPos(veh)
    if not veh or veh == 0 then return nil end
    local model = GetEntityModel(veh)
    if not model or model == 0 then return GetEntityCoords(veh) end
    local minDim, maxDim = GetModelDimensions(model)
    -- length along Y axis; add a small fudge to reach beyond the center
    local halfLen = ((maxDim.y or 0.0) - (minDim.y or 0.0)) * 0.5
    if halfLen <= 0.01 then
        -- fallback: assume ~1.8m half length for small cars
        halfLen = 1.8
    end
    -- safer: use native to transform local offset to world coords
    local front = GetOffsetFromEntityInWorldCoords(veh, 0.0, halfLen, 0.0)
    return front or GetEntityCoords(veh)
end

-- Optional: compute both front-left and front-right nose points for better edge detection
local function GetVehicleNoseWorldPoints(veh)
    local pts = {}
    if not veh or veh == 0 then return pts end
    local model = GetEntityModel(veh)
    if not model or model == 0 then
        pts[1] = GetEntityCoords(veh)
        return pts
    end
    local minDim, maxDim = GetModelDimensions(model)
    local halfLen = ((maxDim.y or 0.0) - (minDim.y or 0.0)) * 0.5
    local halfWid = ((maxDim.x or 0.0) - (minDim.x or 0.0)) * 0.5
    if halfLen <= 0.01 then halfLen = 1.8 end
    if halfWid <= 0.01 then halfWid = 0.9 end
    -- front center
    pts[#pts+1] = GetOffsetFromEntityInWorldCoords(veh, 0.0, halfLen, 0.0)
    -- front corners
    pts[#pts+1] = GetOffsetFromEntityInWorldCoords(veh, halfWid, halfLen, 0.0)
    pts[#pts+1] = GetOffsetFromEntityInWorldCoords(veh, -halfWid, halfLen, 0.0)
    return pts
end

-- Attempt to grant keys for a vehicle across common key resources
-- Keys.Give(veh, plate) is defined in integrations/keys.lua

--------------------------------------------------------------------------------
-- 6) notifications live in integrations/notify.lua (Notify)
--------------------------------------------------------------------------------
-- 7) COUNTDOWN UI
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 8) LOBBY PED & TARGET SETUP
--------------------------------------------------------------------------------
CreateThread(function()
    local cfg = Config.LobbyPed
    RequestModel(cfg.model)
    while not HasModelLoaded(cfg.model) do Wait(0) end

    local ped = CreatePed(0, cfg.model, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    Target.AddPed(ped, {
      { name = 'roxwood_create_lobby', event = 'dps-roxwoodracing:client:createLobby', icon = 'fa-solid fa-flag-checkered', label = Locale("create_lobby"), canInteract = function() return not hasLobby end, distance = 2.5 },
      { name = 'roxwood_join_lobby',   event = 'dps-roxwoodracing:client:joinLobby',   icon = 'fa-solid fa-user-plus',       label = Locale("join_lobby"),   canInteract = function() return hasLobby and not currentLobby end, distance = 2.5 },
    })
    local blip = AddBlipForCoord(cfg.coords.x, cfg.coords.y, cfg.coords.z)
    SetBlipSprite(blip, 315); SetBlipDisplay(blip, 4); SetBlipScale(blip, 0.8); SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING"); AddTextComponentString(Locale('blip_name')); EndTextCommandSetBlipName(blip)
end)

--------------------------------------------------------------------------------
-- 9) LOBBY STATE HANDLERS
--------------------------------------------------------------------------------
RegisterNetEvent('dps-roxwoodracing:setLobbyState', function(state)
    hasLobby = state
    if not state then currentLobby, lobbyOwner = nil, nil end
end)
RegisterNetEvent('dps-roxwoodracing:updateLobbyInfo', function(info)
    if inRace then
        -- Don't show lobby window during a race
        return
    end
    if info and info.name then
        hasLobby     = true
        currentLobby = info.name
        lobbyOwner   = info.owner
        -- Show persistent lobby window with current players.
        -- Prefer server-supplied character names (info.names) over local Steam-name lookup.
        local names = {}
        if info.names then
            for i, n in ipairs(info.names) do
                names[i] = (n and n ~= "") and n or ("ID" .. (info.players and info.players[i] or i))
            end
        elseif info.players then
            for _, sid in ipairs(info.players) do
                local pid   = GetPlayerFromServerId(sid)
                local pname = pid and GetPlayerName(pid) or ("ID"..sid)
                table.insert(names, pname)
            end
        end
    local displayName = info and info.hostName or "UnknownHost"
    if Config.DebugPrints then
        print("[DEBUG] ShowLobbyDisplay called: hostName=" .. tostring(displayName) .. ", members=" .. table.concat(names, ", "))
    end
    ShowLobbyDisplay(displayName, names)
    else
        hasLobby, currentLobby, lobbyOwner = false, nil, nil
        HideLobbyDisplay()
    end
end)

--------------------------------------------------------------------------------
-- 10) CREATE / JOIN / START / LEAVE
-- Ensure lobby info is requested on player spawn/login
AddEventHandler('playerSpawned', function()
    local lobbies = lib.callback.await("dps-roxwoodracing:getLobbies", true)
    if lobbies and #lobbies > 0 then
        -- If there are lobbies, update local state so join option is available
        hasLobby = true
        -- Optionally, you can auto-show the join dialog or notify the player
    else
        hasLobby = false
    end
end)
--------------------------------------------------------------------------------
RegisterNetEvent('dps-roxwoodracing:client:createLobby', function()
    if Config.DebugPrints then
        print("[DEBUG] dps-roxwoodracing:client:createLobby event triggered")
    end
    if hasLobby then
        Notify(Locale("lobby_exists"), "", "error")
        return
    end
    -- Build race class options from config
    local classOpts = {}
    for key, cls in pairs(Config.RaceClasses) do
        table.insert(classOpts, { value = key, label = cls.label .. " - " .. cls.description })
    end
    -- Sort so "Open Class" (All) is first
    table.sort(classOpts, function(a, b)
        if a.value == "All" then return true end
        if b.value == "All" then return false end
        return a.label < b.label
    end)

    local dialog = lib.inputDialog(Locale("create_lobby"), {
        { type = 'number', label = Locale("number_of_laps"), required = true, min = 1, max = 10, default = 3 },
        { type = 'select', label = Locale("select_track"),   required = true, default = 'Short_Track',
          options = {
              { value = 'Short_Track', label = Locale("Short_Track") },
              { value = 'Drift_Track', label = Locale("Drift_Track") },
              { value = 'Speed_Track', label = Locale("Speed_Track") },
              { value = 'Long_Track',  label = Locale("Long_Track")  },
          },
        },
        { type = 'select', label = Locale("select_class"), required = true, default = 'All', options = classOpts },
    })
    if not dialog then if Config.DebugPrints then print("[DEBUG] input dialog cancelled") end return end

    local lapCount   = tonumber(dialog[1]) or 1
    local trackType  = dialog[2]
    local raceClass  = dialog[3] or 'All'
    local rawName = GetPlayerName(PlayerId()) or "Racer"
    local safeName = rawName:gsub("[^%w_]", "_"):sub(1, 30)
    if safeName == "" then safeName = "Racer" end
    local lobbyName = safeName .. "_" .. math.random(1000,9999)
    if Config.DebugPrints then
        print(string.format("[DEBUG] TriggerServerEvent dps-roxwoodracing:createLobby: lobbyName=%s, trackType=%s, lapCount=%s, raceClass=%s", lobbyName, trackType, lapCount, raceClass))
    end
    TriggerServerEvent("dps-roxwoodracing:createLobby", lobbyName, trackType, lapCount, raceClass)
end)

RegisterNetEvent('dps-roxwoodracing:client:joinLobby', function()
    local lobbies = lib.callback.await("dps-roxwoodracing:getLobbies", true)
    if not lobbies or #lobbies == 0 then
        Notify(Locale("no_lobbies"), "", "error")
        return
    end
    local opts = {}
    for _, e in ipairs(lobbies) do table.insert(opts, { value = e.value, label = e.label }) end
    local dialog = lib.inputDialog(Locale("join_lobby"), {
        { type = 'select', label = Locale("select_lobby"), required = true, options = opts },
    })
    if dialog and dialog[1] then
        TriggerServerEvent("dps-roxwoodracing:joinLobby", dialog[1])
    end
end)

RegisterNetEvent('dps-roxwoodracing:client:startRace', function()
    if lobbyOwner ~= GetPlayerServerId(PlayerId()) then
        Notify("", Locale("not_authorized_to_start_race"), "error")
        return
    end
    -- Hide lobby preview for the host immediately
    HideLobbyDisplay()
    CloseVehicleSelectionUI()
    local players = lib.callback.await("dps-roxwoodracing:getLobbyPlayers", false, currentLobby)
    local names   = {}
    for _, sid in ipairs(players) do
        local pid   = GetPlayerFromServerId(sid)
        local pname = pid and GetPlayerName(pid) or ("ID"..sid)
        table.insert(names, pname)
    end
    Notify(Locale("lobby_preview"), table.concat(names, "\n"), "inform", 10000)
    -- No ox_lib context menu to close; lobby window is native
    TriggerServerEvent("dps-roxwoodracing:startRace", currentLobby)
end)

-- Hide lobby preview for all players on server signal
RegisterNetEvent('dps-roxwoodracing:hideLobbyWindow', function()
    HideLobbyDisplay()
    CloseVehicleSelectionUI()
    -- Ensure interact mode is off
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'lobbyFocus', on = false })
end)

-- Vehicle selection countdown overlay
local selectCountdownActive = false
local selectCountdownRemain = 0
local timeoutModalActive = false

RegisterNetEvent("dps-roxwoodracing:vehicleSelectCountdown", function(remaining)
    selectCountdownActive = remaining and remaining > 0
    selectCountdownRemain = remaining or 0
    if selectCountdownActive == false then
        CloseVehicleSelectionUI()
    end
end)

-- If race proceeds, ensure countdown hides
AddEventHandler("dps-roxwoodracing:prepareStart", function()
    selectCountdownActive = false
    CloseVehicleSelectionUI()
end)

CreateThread(function()
    while true do
        Wait(0)
        if selectCountdownActive then
            local sec = math.max(0, tonumber(selectCountdownRemain) or 0)
            SetTextFont(4); SetTextScale(0.5,0.5); SetTextCentre(true)
            SetTextColour(255,200,50,255); SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString((Locale('select_vehicle_timer_fmt')):format(sec))
            DrawText(0.5, 0.12)
        end
    end
end)

-- Notify if kicked due to timeout
RegisterNetEvent("dps-roxwoodracing:kickedFromLobby", function(lobbyName, reason)
    hasLobby, currentLobby, lobbyOwner = false, nil, nil
    HideLobbyDisplay()
    CloseVehicleSelectionUI()
    local message = reason == "timeout" and Locale("vehicle_select_timeout") or Locale("removed_from_lobby")
    -- Show blocking modal requiring player to acknowledge
    timeoutModalActive = true
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showTimeoutModal', message = message })
    -- Keep focus on our modal until dismissed
    CreateThread(function()
        while timeoutModalActive do
            SetNuiFocus(true, true)
            Wait(0)
        end
    end)
end)

-- NUI callback when player clicks Dismiss on the blocking modal
RegisterNUICallback('timeoutDismiss', function(_, cb)
    SendNUIMessage({ action = 'hideTimeoutModal' })
    timeoutModalActive = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    cb('ok')
end)

--------------------------------------------------------------------------------
-- Auto-interact with lobby panel while holding target (Left Alt) near the lobby ped
--------------------------------------------------------------------------------
local autoFocusActive = false
speedwaySuppressAutoUntilAltUp = false

-- Removed Alt long-press simulated targeting loop; use F6 toggle for reliable interaction

RegisterNetEvent('dps-roxwoodracing:client:leaveLobby', function()
    if not hasLobby then
        Notify(Locale("no_lobby_joined"), Locale("no_lobby_joined_desc"), "error")
        return
    end
    TriggerServerEvent("dps-roxwoodracing:leaveLobby", currentLobby)
end)

--------------------------------------------------------------------------------
-- 11) VEHICLE SELECTION
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:chooseVehicle", function(lobbyName, raceClass)
    -- Filter vehicles by race class if specified
    local allowedModels = nil
    if raceClass and Config.RaceClasses[raceClass] and Config.RaceClasses[raceClass].vehicles then
        allowedModels = {}
        for _, m in ipairs(Config.RaceClasses[raceClass].vehicles) do
            allowedModels[m:lower()] = true
        end
    end

    local opts = {}
    for _, v in ipairs(Config.RaceVehicles) do
        if not allowedModels or allowedModels[v.model:lower()] then
            table.insert(opts, { value = v.model, label = v.label })
        end
    end

    if #opts == 0 then
        -- Fallback to all vehicles if class filter yields nothing
        for _, v in ipairs(Config.RaceVehicles) do
            table.insert(opts, { value = v.model, label = v.label })
        end
    end

    local dialog = lib.inputDialog(Locale("choose_vehicle_title"), {
        { type = 'select', label = Locale("choose_vehicle_label"), required = true, options = opts, default = opts[1].value },
    })
    local sel = dialog and dialog[1] or nil
    TriggerServerEvent("dps-roxwoodracing:selectedVehicle", lobbyName, sel)
end)

--------------------------------------------------------------------------------
-- 12) PREPARE & START THE RACE (SPAWN + COUNTDOWN)
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:prepareStart", function(data)
    -- Hide lobby preview window for everyone once the race is about to start
    HideLobbyDisplay()
    -- Stop vehicle selection countdown if showing
    selectCountdownActive = false
    inRace       = true
    currentTrack = data.track
    -- Initialize HUD lap counters using payload laps so HUD shows 1/x from start
    currentLap   = 1
    totalLaps    = tonumber(data.laps) or totalLaps or 1

    -- clear old props
    TriggerEvent("dps-roxwoodracing:client:destroyprops")

    -- spawn new props...
    for _, pd in ipairs(Config.TrackProps[data.track] or {}) do
        RequestModel(pd.prop); while not HasModelLoaded(pd.prop) do Wait(0) end
        for _, c in ipairs(pd.cords) do
            local obj = CreateObject(pd.prop, c.x, c.y, c.z - 1.0, false, false, false)
            SetEntityAsMissionEntity(obj, true, true)
            PlaceObjectOnGroundProperly(obj); SetEntityHeading(obj, c.w); FreezeEntityPosition(obj, true)
            table.insert(currentProps, obj)
        end
    end

    -- checkpoint spheres
    racerCheckpointIndex = 0
    -- clear any previous zones before creating new ones (safety)
    for _, z in ipairs(currentZones) do
        if z and z.remove then pcall(function() z:remove() end) end
    end
    currentZones = {}

    for idx, coord in ipairs(Config.Checkpoints[data.track] or {}) do
        local z = lib.zones.sphere({
            coords = coord, radius = 15.0, debug = Config.ZoneDebug,
            onEnter = function()
                if idx == racerCheckpointIndex + 1 then
                    racerCheckpointIndex = idx
                    TriggerServerEvent("dps-roxwoodracing:checkpointPassed", currentLobby, idx)
                end
            end
        })
        table.insert(currentZones, z)
    end

    -- finish line sphere
    local finishZone = lib.zones.sphere({
        name   = "finish_line",
        coords = Config.FinishLine.coords,
        radius = Config.FinishLine.radius,
        debug  = Config.ZoneDebug,
        onEnter = function()
            if racerCheckpointIndex == #Config.Checkpoints[data.track] then
                racerCheckpointIndex = 0
                TriggerServerEvent("dps-roxwoodracing:lapPassed", currentLobby)
            end
        end
    })
    table.insert(currentZones, finishZone)

    -- now spawn & race
    CreateThread(function()
        -- wait for the vehicle entity to exist (with 15s timeout)
        local deadline = GetGameTimer() + 15000
        while not NetworkDoesNetworkIdExist(data.netId) do
          if GetGameTimer() > deadline then
            Notify("Speedway", "Vehicle failed to spawn. Please try again.", "error", 5000)
            inRace = false
            return
          end
          Wait(0)
        end
        local veh = NetworkGetEntityFromNetworkId(data.netId)
        while not DoesEntityExist(veh) do
          if GetGameTimer() > deadline then
            Notify("Speedway", "Vehicle failed to spawn. Please try again.", "error", 5000)
            inRace = false
            return
          end
          Wait(0)
          veh = NetworkGetEntityFromNetworkId(data.netId)
        end

    -- Store our race vehicle handle for ghosting
    myRaceVeh = veh

    -- prep vehicle
    SetEntityAsMissionEntity(veh, true, true)
    FreezeEntityPosition(veh, true)
    -- Give keys as early as possible (before any engine state changes)
    Keys.Give(veh, data.plate)

    -- Apply fuel and full cosmetics BEFORE putting the player in to avoid visible pop
    Fuel.SetFull(veh)
    if Speedway_ApplyAll then Speedway_ApplyAll(veh) end
    -- Engine ON before countdown so drivers can launch instantly at GO
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleUndriveable(veh, true)

    -- Put player in the vehicle after customization
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    repeat Wait(0) until IsPedInAnyVehicle(PlayerPedId(), false)

    -- (keys were already granted before customization)

    -- Force-unlock on client as well (some key scripts toggle later)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)

        -- Apply the desired name-based plate AFTER cosmetics to avoid any overwrite
        local desiredPlate = (data and data.plate) or (GetVehicleNumberPlateText(veh) or "")
        if desiredPlate and desiredPlate ~= "" then
            SetVehicleNumberPlateText(veh, desiredPlate)
            if Config.DebugPrints then
                print(("[DEBUG] Applied name plate after cosmetics -> '%s'"):format(tostring(desiredPlate)))
            end
            -- Reassert a couple times to fight streaming/ownership races
            CreateThread(function()
                local untilTs = GetGameTimer() + 800
                while GetGameTimer() < untilTs and DoesEntityExist(veh) do
                    SetVehicleNumberPlateText(veh, desiredPlate)
                    Wait(120)
                end
            end)
        end

        -- Reassert FULL FUEL for a short window in case other scripts set it later
        CreateThread(function()
            local untilTs = GetGameTimer() + 2500
            while GetGameTimer() < untilTs and DoesEntityExist(veh) do
                Fuel.SetFull(veh)
                Wait(200)
            end
        end)

        -- Keep doors unlocked during initialization for a short window to override scripts
        CreateThread(function()
            local tEnd = GetGameTimer() + 3000
            while GetGameTimer() < tEnd and DoesEntityExist(veh) do
                SetVehicleDoorsLocked(veh, 1)
                SetVehicleDoorsLockedForAllPlayers(veh, false)
                SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
                Wait(150)
            end
        end)

        -- countdown
            -- Use configurable race start delay
            local delay = Config.RaceStartDelay or 3
            for i = delay, 1, -1 do
                FreezeEntityPosition(veh, true)
                -- Keep engine running during countdown
                SetVehicleEngineOn(veh, true, true, false)
                ShowCountdownText(tostring(i), 1000)
            end
            ShowCountdownText("GO", 1000)
            FreezeEntityPosition(veh, false)
            SetVehicleUndriveable(veh, false)
            SetVehicleHandbrake(veh, false)

        -- Start ghosting at GO if enabled
        if Config.Ghosting.enabled and Config.Ghosting.startGhosted then
            StartGhostThread()
        end

        -- Post-GO safety: briefly assert drivability and unlock state without touching engine
        CreateThread(function()
            local untilTs = GetGameTimer() + 3000
            while GetGameTimer() < untilTs and DoesEntityExist(veh) do
                FreezeEntityPosition(veh, false)
                SetVehicleUndriveable(veh, false)
                SetVehicleHandbrake(veh, false)
                SetVehicleDoorsLocked(veh, 1)
                SetVehicleDoorsLockedForAllPlayers(veh, false)
                SetVehicleDoorsLockedForPlayer(veh, PlayerId(), false)
                Wait(100)
            end
        end)

    -- No key or cosmetic changes after GO to avoid any side-effects

    -- (fuel/cosmetics were already applied before entering the vehicle)

        -- start progress reporter
        CreateThread(function()
            while inRace do
                local v = GetVehiclePedIsIn(PlayerPedId(), false)
                if v and v ~= 0 then
                    -- Use nose points to decide the most advanced extreme
                    local dist
                    if Config.DistanceUseNoseCorners then
                        local pts = GetVehicleNoseWorldPoints(v)
                        local best = 0.0
                        for _, p in ipairs(pts) do
                            local d = ComputeDistanceAlongTrack(p)
                            if d > best then best = d end
                        end
                        dist = best
                    else
                        local frontPos = GetVehicleFrontWorldPos(v) or GetEntityCoords(v)
                        dist = ComputeDistanceAlongTrack(frontPos)
                    end
                    if Config.DebugPrints then
                        print(("[DEBUG] updateProgress dist=%.2f lobby=%s"):format(dist, tostring(currentLobby)))
                    end
                    TriggerServerEvent("dps-roxwoodracing:updateProgress", currentLobby, dist)
                end
                Wait(Config.ProgressTickMs or 200)
            end
        end)
    end)
end)

-- Cleanup: remove spawned props and any active checkpoint/finish zones
RegisterNetEvent("dps-roxwoodracing:client:destroyprops", function()
    -- End ghosting
    ghostActive = false
    raceNetIds = {}
    myRaceVeh = nil
    -- delete props
    for _, obj in ipairs(currentProps) do
        if obj and DoesEntityExist(obj) then
            DeleteObject(obj)
        end
    end
    currentProps = {}
    -- remove zones
    for _, z in ipairs(currentZones) do
        if z and z.remove then
            pcall(function() z:remove() end)
        end
    end
    currentZones = {}
end)

-- Manual cleanup command (optional): removes any spawned props/zones immediately
RegisterCommand('speedway_cleanup', function()
    TriggerEvent('dps-roxwoodracing:client:destroyprops')
end, false)

RegisterNetEvent("dps-roxwoodracing:youFinished", function()
    Notify("🏁 Speedway", Locale("you_finished"), "success", 5000)
end)

--------------------------------------------------------------------------------
-- 14) FINAL RANKING
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:finalRanking", function(data)
    local results = data.allResults or {}

    -- If ResultsUI is enabled and we have expanded results, use NUI
    if Config.ResultsUI and Config.ResultsUI.enabled and #results > 0 and results[1].name then
        SendNUIMessage({
            action = "showRaceResults",
            results = results,
            bestLapPlayer = data.bestLapPlayer,
            mostImprovedPlayer = data.mostImprovedPlayer,
            track = data.track,
            autoDismissMs = Config.ResultsUI.displayDurationMs or 20000,
        })
        SetNuiFocus(true, true)
        return
    end

    -- Fallback: legacy toast notifications
    if not data.position then
        local lines = { Locale("podium_header") }
        for i,e in ipairs(results) do
            local name = GetPlayerName(GetPlayerFromServerId(e.id)) or ("ID"..e.id)
            lines[#lines+1] = ("%d. %s — %ds"):format(i, name, math.floor(e.time/1000))
        end
        Notify("", table.concat(lines, "\n"), "inform", 10000)
        return
    end

    local totalTime = math.floor((data.totalTime or 0)/1000)
    if data.position == 1 then
        Notify("🏆 Speedway", Locale("you_won", totalTime), "success", 5000)
    else
        Notify("🏁 Speedway", Locale("you_placed", data.position, #results, totalTime), "inform", 5000)
    end
    if data.lapTimes then
        local lapLines = { Locale("lap_summary") }
        for i,t in ipairs(data.lapTimes) do
            lapLines[#lapLines+1] = Locale("lap_time", i, math.floor(t/1000))
        end
        lapLines[#lapLines+1] = Locale("best_lap", math.floor((data.bestLap or 0)/1000))
        Notify(Locale("lap_summary"), table.concat(lapLines, "\n"), "info", 10000)
    end
end)

-- NUI callback: dismiss race results overlay
RegisterNUICallback('resultsClose', function(_, cb)
    SetNuiFocus(false, false)
    if cb then cb('ok') end
end)

--------------------------------------------------------------------------------
-- 15) FINISH TELEPORT
--------------------------------------------------------------------------------
RegisterNetEvent("dps-roxwoodracing:client:finishTeleport", function(coords)
    inRace = false
    ghostActive = false
    myRaceVeh = nil
    CreateThread(function()
        DoScreenFadeOut(1000); while not IsScreenFadedOut() do Wait(0) end

        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local v = GetVehiclePedIsIn(ped, false)
            TaskLeaveVehicle(ped, v, 0); Wait(500)
            if DoesEntityExist(v) then DeleteVehicle(v) end
        end

        SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
        SetEntityHeading(ped, coords.w)
        Wait(500); DoScreenFadeIn(1000)
    end)
end)

--------------------------------------------------------------------------------
-- 16) FUEL AUTO-FILL EVENT
--------------------------------------------------------------------------------

-- Use globals so values set during prepareStart are reflected here too
currentLap, totalLaps = currentLap or 1, totalLaps or 1

RegisterNetEvent("dps-roxwoodracing:updateLap", function(cur, tot)
    currentLap, totalLaps = cur, tot
    Notify("🏁 Speedway", ("Lap %s/%s"):format(cur, tot), "inform", 3000)
end)

RegisterNetEvent("dps-roxwoodracing:updatePosition", function(position, total)
    myPosition = position
    totalRacers = total
    if Config.DebugPrints then
        print(("[DEBUG] updatePosition myPosition=%s total=%s"):format(tostring(myPosition), tostring(totalRacers)))
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if inRace then
            -- Draw position/rank
            SetTextFont(4); SetTextScale(0.5,0.5); SetTextCentre(true)
            SetTextColour(255,255,255,255); SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString( ("Position: %d/%d"):format(myPosition, totalRacers) )
            DrawText(0.5, 0.93)

            -- Draw lap info
            SetTextFont(4); SetTextScale(0.45,0.45); SetTextCentre(true)
            SetTextColour(255,255,255,255); SetTextOutline()
            SetTextEntry("STRING")
            AddTextComponentString( ("Lap: %d/%d"):format(currentLap, totalLaps) )
            DrawText(0.5, 0.96)
        end
    end
end)

--------------------------------------------------------------------------------
-- REWARD NOTIFICATIONS
--------------------------------------------------------------------------------
RegisterNetEvent('dps-roxwoodracing:client:rewardNotify', function(data)
    if data.positionPayout and data.positionPayout > 0 then
        Notify("Speedway", Locale("reward_cash", data.positionPayout, data.positionLabel or ""), "success", 5000)
    end
    if data.participation and data.participation > 0 then
        Notify("Speedway", Locale("reward_participation", data.participation), "inform", 4000)
    end
    if data.bestLapBonus and data.bestLapBonus > 0 then
        Notify("Speedway", Locale("reward_best_lap", data.bestLapBonus), "success", 5000)
    end
    if data.vehiclePrize then
        Notify("Speedway", Locale("reward_vehicle", data.vehiclePrize), "success", 8000)
    end
    if data.poolPayout and data.poolPayout > 0 then
        Notify("Speedway", Locale("prize_pool_payout", data.poolPayout), "success", 5000)
    end
end)

--------------------------------------------------------------------------------
-- STATS DISPLAY
--------------------------------------------------------------------------------
RegisterNetEvent('dps-roxwoodracing:client:statsNotify', function(data)
    if data.newRecord then
        Notify("Speedway", Locale("stats_new_record", string.format("%.1f", data.newRecord / 1000)), "success", 6000)
    end
    if data.wins and data.totalRaces then
        local bestStr = data.bestLap and string.format("%.1f", data.bestLap / 1000) or "N/A"
        Notify("Speedway", Locale("stats_summary", data.wins, data.totalRaces, bestStr), "inform", 8000)
    end
end)

-- /racestats command to view personal stats
RegisterCommand('racestats', function()
    local stats = lib.callback.await('dps-roxwoodracing:getPlayerStats', false)
    if not stats then
        Notify("Speedway", "No stats found.", "error", 3000)
        return
    end
    local lines = { Locale("stats_command_header") }
    lines[#lines+1] = ("Races: %d | Wins: %d | Top 3: %d"):format(stats.total_races or 0, stats.wins or 0, stats.top3 or 0)
    lines[#lines+1] = ("Total Earnings: $%d"):format(stats.total_earnings or 0)
    if stats.best_laps then
        for track, ms in pairs(stats.best_laps) do
            lines[#lines+1] = ("%s Best: %.1fs"):format(track, ms / 1000)
        end
    end
    Notify(Locale("stats_command_header"), table.concat(lines, "\n"), "inform", 12000)
end, false)

--------------------------------------------------------------------------------
-- STAFF: Raceway Control (boss menu item + /raceway)
--------------------------------------------------------------------------------
local function openControl()
  if not Bridge.HasJob(Config.Job.name, Config.Job.grades.marshal) then Notify(Config.Job.label, Locale('staff_only'), 'error') return end
  local snap = lib.callback.await('dps-roxwoodracing:staff:snapshot', false)
  if not snap then return end
  local options = {}
  for _, l in ipairs(snap.lobbies) do
    options[#options+1] = { title = ('%s  %s  %s  %d racers'):format(l.name, l.track, l.mode, l.players), description = l.started and 'Running' or 'Waiting',
      onSelect = function()
        local pick = lib.inputDialog(l.name, { { type = 'select', label = 'Action', required = true, options = { { value = 'endRace', label = 'End race' }, { value = 'names', label = 'Sign: names' }, { value = 'toggle', label = 'Sign: names + times' } } } })
        if not pick then return end
        if pick[1] == 'endRace' then TriggerServerEvent('dps-roxwoodracing:staff:action', 'endRace', { lobby = l.name })
        else TriggerServerEvent('dps-roxwoodracing:staff:action', 'signMode', { lobby = l.name, mode = pick[1] }) end
      end }
  end
  options[#options+1] = { title = 'Clear track props', icon = 'broom', onSelect = function() TriggerServerEvent('dps-roxwoodracing:staff:action', 'clearProps') end }
  if Bridge.HasJob(Config.Job.name, Config.Job.grades.director) then
    options[#options+1] = { title = ('Account balance: $%s'):format(snap.balance), description = ('Purse source: %s'):format(snap.purseSource), disabled = true }
    local fields = { { 'entryfee', 'Entry fee' }, { 'payout1', '1st place' }, { 'payout2', '2nd place' }, { 'payout3', '3rd place' }, { 'showup', 'Show-up bonus' }, { 'bestlap', 'Fastest lap bonus' } }
    for _, f in ipairs(fields) do
      options[#options+1] = { title = ('%s: $%s'):format(f[2], snap[f[1]]), onSelect = function()
        local v = lib.inputDialog(f[2], { { type = 'number', label = 'Amount', default = snap[f[1]], min = 0 } })
        if v and v[1] then TriggerServerEvent('dps-roxwoodracing:staff:action', 'setSetting', { key = f[1], value = v[1] }) end
      end }
    end
  end
  lib.registerContext({ id = 'dps_roxwoodracing_control', title = Locale('raceway_control'), options = options })
  lib.showContext('dps_roxwoodracing_control')
end
RegisterNetEvent('dps-roxwoodracing:client:openControl', openControl)
RegisterCommand('raceway', openControl, false)
