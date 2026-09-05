-- Stubs for FiveM globals so shared/ and pure server modules load under lua5.4.
STUB = { started = {}, clientEvents = {}, queries = {}, prints = {} }
function GetResourceState(name) return STUB.started[name] and 'started' or 'missing' end
function GetCurrentResourceName() return 'dps-roxwoodracing' end
function GetInvokingResource() return 'dps-roxwoodracing' end
function IsDuplicityVersion() return true end
function GetGameTimer() return STUB.now or 0 end
function GetPlayerName(pid) return 'Rockstar' .. tostring(pid) end
function TriggerClientEvent(name, target, ...) STUB.clientEvents[#STUB.clientEvents+1] = { name = name, target = target, args = { ... } } end
function TriggerEvent() end
function RegisterNetEvent() end
function AddEventHandler() end
function RegisterCommand() end
function NetworkGetEntityFromNetworkId() return 0 end
function CreateThread(fn) fn() end
function Wait() end
function joaat(s) return 0 end
Locale = Locale or function(k) return k end
-- exports: exports['res']:Fn(...) and exports.res:Fn(...)
exports = setmetatable({}, { __index = function(t, k) return STUB.exports and STUB.exports[k] end })
lib = { callback = { register = function() end }, print = { warn = function() end, info = function() end } }
-- oxmysql stub records queries and returns canned rows
MySQL = {
  query  = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.rows or {} end },
  single = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.row end },
  insert = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return 1 end },
  scalar = { await = function(sql, params) STUB.queries[#STUB.queries+1] = { sql = sql, params = params }; return STUB.scalar end },
}
json = { encode = function(t) local parts = {} for k, v in pairs(t) do parts[#parts+1] = ('"%s":%s'):format(k, tostring(v)) end return '{' .. table.concat(parts, ',') .. '}' end,
         decode = function(s) local t = {} for k, v in s:gmatch('"([^"]+)":([%d%.]+)') do t[k] = tonumber(v) end return t end }
function vector3(x, y, z) return { x = x, y = y, z = z } end
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec3 = vector3
function RESET_STUB() STUB.started = {}; STUB.clientEvents = {}; STUB.queries = {}; STUB.rows = nil; STUB.row = nil; STUB.exports = {}; STUB.now = 0; STUB.scalar = nil end
RESET_STUB()
