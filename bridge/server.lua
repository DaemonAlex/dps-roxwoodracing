-- Server framework bridge. qbx and qb share the QB player-object shape.
Bridge = Bridge or {}
local fw = Bridge.Framework

local function getPlayer(pid)
  if fw == 'qbx' then return exports.qbx_core:GetPlayer(pid) end
  if fw == 'qb' then return exports['qb-core']:GetCoreObject().Functions.GetPlayer(pid) end
  return nil
end

local function esx()
  return exports['es_extended']:getSharedObject()
end

local function mapMoneyType(mtype)
  if fw == 'esx' and mtype == 'cash' then return 'money' end
  return mtype or 'cash'
end

function Bridge.GetPlayerIdentifier(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    return x and x.getIdentifier() or nil
  end
  return nil
end

function Bridge.GetPlayerName(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local ci = P and P.PlayerData and P.PlayerData.charinfo
    if ci then return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$') end
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    if x and x.getName() then return x.getName() end
  end
  return GetPlayerName(pid) or ('Player ' .. tostring(pid))
end

function Bridge.GetPlayerFirstLast(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local ci = P and P.PlayerData and P.PlayerData.charinfo
    if ci then return ci.firstname, ci.lastname end
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid)
    local name = x and x.getName()
    if name then return name:match('^(%S+)%s*(.*)$') end
  end
  return nil, nil
end

function Bridge.AddMoney(pid, mtype, amount, reason)
  if amount <= 0 then return true end
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid); if not P then return false end
    return P.Functions.AddMoney(mapMoneyType(mtype), amount, reason) ~= false
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return false end
    if mapMoneyType(mtype) == 'bank' then x.addAccountMoney('bank', amount) else x.addMoney(amount) end
    return true
  end
  return false
end

function Bridge.RemoveMoney(pid, mtype, amount, reason)
  if amount <= 0 then return true end
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid); if not P then return false end
    return P.Functions.RemoveMoney(mapMoneyType(mtype), amount, reason) ~= false
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return false end
    local have = mapMoneyType(mtype) == 'bank' and x.getAccount('bank').money or x.getMoney()
    if have < amount then return false end
    if mapMoneyType(mtype) == 'bank' then x.removeAccountMoney('bank', amount) else x.removeMoney(amount) end
    return true
  end
  return false
end

function Bridge.GetMoney(pid, mtype)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    return P and P.Functions.GetMoney(mapMoneyType(mtype)) or 0
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return 0 end
    if mapMoneyType(mtype) == 'bank' then return x.getAccount('bank').money end
    return x.getMoney()
  end
  return 0
end

-- Pay a character by identifier even when they are offline (qbx supports this natively).
function Bridge.AddMoneyByIdentifier(identifier, mtype, amount, reason)
  if amount <= 0 then return true end
  if fw == 'qbx' then
    local ok, res = pcall(function() return exports.qbx_core:AddMoney(identifier, mapMoneyType(mtype), amount, reason) end)
    return ok and res == true
  elseif fw == 'qb' then
    local P = exports['qb-core']:GetCoreObject().Functions.GetPlayerByCitizenId(identifier)
    if not P then return false end
    return P.Functions.AddMoney(mapMoneyType(mtype), amount, reason) ~= false
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromIdentifier(identifier)
    if not x then return false end
    if mapMoneyType(mtype) == 'bank' then x.addAccountMoney('bank', amount) else x.addMoney(amount) end
    return true
  end
  return false
end

function Bridge.GetJob(pid)
  if fw == 'qbx' or fw == 'qb' then
    local P = getPlayer(pid)
    local j = P and P.PlayerData and P.PlayerData.job
    if not j then return nil end
    local grade = type(j.grade) == 'table' and (j.grade.level or 0) or (tonumber(j.grade) or 0)
    return { name = j.name, grade = grade, isboss = j.isboss == true }
  elseif fw == 'esx' then
    local x = esx().GetPlayerFromId(pid); if not x then return nil end
    local j = x.getJob()
    return { name = j.name, grade = j.grade or 0, isboss = (j.grade_name == 'boss') }
  end
  return nil
end

function Bridge.HasJob(pid, jobName, minGrade)
  local j = Bridge.GetJob(pid)
  return j ~= nil and j.name == jobName and j.grade >= (minGrade or 0)
end

-- Character name lookup for offline players (leaderboard idle view).
function Bridge.GetPlayerNameFromDB(identifier)
  if fw == 'qbx' or fw == 'qb' then
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
    if row and row.charinfo then
      local ci = json.decode(row.charinfo)
      if ci then return ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$') end
    end
  elseif fw == 'esx' then
    local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
    if row then return ((row.firstname or '') .. ' ' .. (row.lastname or '')):match('^%s*(.-)%s*$') end
  end
  return nil
end
