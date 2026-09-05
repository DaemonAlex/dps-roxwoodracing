-- sv_bridge.lua
-- Framework bridge: auto-detects QBCore/QBX or ESX and exposes a unified API.
-- Loaded before all other server scripts via fxmanifest.

Bridge = {}

-- Config is a shared global

--------------------------------------------------------------------------------
-- Framework detection
--------------------------------------------------------------------------------
local fw = Config.Framework -- manual override from config (nil = auto-detect)

if not fw then
    if GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
        fw = 'qbcore'
    elseif GetResourceState('qbx_core') == 'started' or GetResourceState('qbx_core') == 'starting' then
        fw = 'qbcore' -- QBX exposes the same QBCore API
    elseif GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
        fw = 'esx'
    end
end

Bridge.Framework = fw

-- Framework objects (lazy-loaded once)
local QBCore, ESX

if fw == 'qbcore' then
    if GetResourceState('qbx_core') == 'started' or GetResourceState('qbx_core') == 'starting' then
        -- QBX dropped GetCoreObject; build a shim from its direct exports
        -- so the rest of the bridge can use QBCore.Functions.* uniformly
        local qbx = exports['qbx_core']
        QBCore = {
            Functions = {
                GetPlayer = function(src) return qbx:GetPlayer(src) end,
                GetQBPlayers = function()
                    local result = {}
                    for _, pidStr in ipairs(GetPlayers()) do
                        local src = tonumber(pidStr)
                        if src then
                            local p = qbx:GetPlayer(src)
                            if p then result[src] = p end
                        end
                    end
                    return result
                end,
            }
        }
    elseif GetResourceState('qb-core') == 'started' or GetResourceState('qb-core') == 'starting' then
        QBCore = exports['qb-core']:GetCoreObject()
    else
        print('[Speedway] WARNING: Framework set to qbcore but neither qb-core nor qbx_core is running!')
        fw = nil
        Bridge.Framework = nil
    end
elseif fw == 'esx' then
    if GetResourceState('es_extended') == 'started' or GetResourceState('es_extended') == 'starting' then
        ESX = exports['es_extended']:getSharedObject()
    else
        print('[Speedway] WARNING: Framework set to esx but es_extended is not running!')
        fw = nil
        Bridge.Framework = nil
    end
end

print(('[Speedway] Framework detected: %s'):format(fw or 'none'))

--------------------------------------------------------------------------------
-- Money type mapping: QBCore 'cash' = ESX 'money', 'bank' = 'bank' in both
--------------------------------------------------------------------------------
local function mapMoneyType(mtype)
    if fw == 'esx' and mtype == 'cash' then return 'money' end
    return mtype or 'cash'
end

--------------------------------------------------------------------------------
-- Bridge.GetPlayerIdentifier(pid)
-- Returns the character-unique identifier (citizenid or ESX identifier).
--------------------------------------------------------------------------------
function Bridge.GetPlayerIdentifier(pid)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player and Player.PlayerData then
            return Player.PlayerData.citizenid
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            return xPlayer.getIdentifier()
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Bridge.GetPlayerName(pid)
-- Returns "Firstname Lastname" from the framework's character data.
--------------------------------------------------------------------------------
function Bridge.GetPlayerName(pid)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            local ci = Player.PlayerData.charinfo
            return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            local name = xPlayer.getName()
            if name then return name end
        end
    end
    return GetPlayerName(pid) or ('Player ' .. pid)
end

--------------------------------------------------------------------------------
-- Bridge.GetPlayerFirstLast(pid)
-- Returns first, last separately (used for plate generation).
--------------------------------------------------------------------------------
function Bridge.GetPlayerFirstLast(pid)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            return Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            local name = xPlayer.getName()
            if name then
                local first, last = name:match('^(%S+)%s*(.*)$')
                return first, last
            end
        end
    end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Bridge.AddMoney(pid, type, amount, reason)
--------------------------------------------------------------------------------
function Bridge.AddMoney(pid, mtype, amount, reason)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player then
            Player.Functions.AddMoney(mtype, amount, reason)
            return true
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            local esxType = mapMoneyType(mtype)
            if esxType == 'money' then
                xPlayer.addMoney(amount)
            else
                xPlayer.addAccountMoney(esxType, amount)
            end
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Bridge.RemoveMoney(pid, type, amount, reason)
--------------------------------------------------------------------------------
function Bridge.RemoveMoney(pid, mtype, amount, reason)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player then
            Player.Functions.RemoveMoney(mtype, amount, reason)
            return true
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            local esxType = mapMoneyType(mtype)
            if esxType == 'money' then
                xPlayer.removeMoney(amount)
            else
                xPlayer.removeAccountMoney(esxType, amount)
            end
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Bridge.GetMoney(pid, type)
--------------------------------------------------------------------------------
function Bridge.GetMoney(pid, mtype)
    if fw == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(pid)
        if Player then
            return Player.Functions.GetMoney(mtype)
        end
    elseif fw == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(pid)
        if xPlayer then
            local esxType = mapMoneyType(mtype)
            if esxType == 'money' then
                return xPlayer.getMoney()
            else
                local account = xPlayer.getAccount(esxType)
                return account and account.money or 0
            end
        end
    end
    return 0
end

--------------------------------------------------------------------------------
-- Bridge.GetAllPlayersWithIdentifier()
-- Returns { [identifier] = pid } for all online players.
--------------------------------------------------------------------------------
function Bridge.GetAllPlayersWithIdentifier()
    local map = {}
    if fw == 'qbcore' then
        local players = QBCore.Functions.GetQBPlayers and QBCore.Functions.GetQBPlayers() or {}
        for _, player in pairs(players) do
            if player and player.PlayerData and player.PlayerData.citizenid then
                map[player.PlayerData.citizenid] = player.PlayerData.source
            end
        end
    elseif fw == 'esx' then
        local players = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or {}
        for _, xPlayer in pairs(players) do
            if xPlayer then
                map[xPlayer.getIdentifier()] = xPlayer.source
            end
        end
    end
    return map
end

--------------------------------------------------------------------------------
-- Bridge.GetPlayerNameFromDB(identifier)
-- Looks up a player name from the database by identifier (offline lookup).
-- Returns "Firstname Lastname" or nil.
--------------------------------------------------------------------------------
function Bridge.GetPlayerNameFromDB(identifier)
    if not identifier then return nil end

    if fw == 'qbcore' then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
        if row and row.charinfo then
            local ci = json.decode(row.charinfo)
            if ci then
                return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
            end
        end
    elseif fw == 'esx' then
        local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
        if row then
            return ((row.firstname or '') .. ' ' .. (row.lastname or '')):match('^%s*(.-)%s*$')
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Bridge.InsertVehicle(pid, model, plate)
-- Inserts a vehicle into the player's garage via the framework's DB schema.
--------------------------------------------------------------------------------
function Bridge.InsertVehicle(pid, model, plate, garage)
    local identifier = Bridge.GetPlayerIdentifier(pid)
    if not identifier then return false end

    if fw == 'qbcore' then
        MySQL.insert.await(
            'INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            {
                GetPlayerIdentifierByType(pid, 'license') or '',
                identifier,
                model,
                tostring(joaat(model)),
                '{}',
                plate,
                garage or 'pillboxgarage',
                0,
            }
        )
    elseif fw == 'esx' then
        MySQL.insert.await(
            'INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?)',
            {
                identifier,
                plate,
                json.encode({ model = joaat(model), plate = plate }),
            }
        )
    end

    return true
end
