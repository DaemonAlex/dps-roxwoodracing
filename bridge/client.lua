-- Client framework bridge: job lookups only.
Bridge = Bridge or {}
local fw = Bridge.Framework

function Bridge.GetJob()
  local pd
  if fw == 'qbx' then pd = exports.qbx_core:GetPlayerData()
  elseif fw == 'qb' then pd = exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
  elseif fw == 'esx' then pd = exports['es_extended']:getSharedObject().GetPlayerData() end
  local j = pd and pd.job
  if not j then return nil end
  if fw == 'esx' then return { name = j.name, grade = j.grade or 0, isboss = (j.grade_name == 'boss') } end
  return { name = j.name, grade = (type(j.grade) == 'table' and j.grade.level) or tonumber(j.grade) or 0, isboss = j.isboss == true }
end

function Bridge.HasJob(jobName, minGrade)
  local j = Bridge.GetJob()
  return j ~= nil and j.name == jobName and j.grade >= (minGrade or 0)
end
