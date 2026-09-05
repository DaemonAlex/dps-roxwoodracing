local function loadBridge()
  Config = { Framework = nil }
  Bridge = nil
  dofile('bridge/init.lua')
  dofile('bridge/server.lua')
end

TEST('detects qbx before qb', function()
  RESET_STUB(); STUB.started = { qbx_core = true, ['qb-core'] = true }
  loadBridge()
  EQ(Bridge.Framework, 'qbx')
end)

TEST('qbx money and job go through exports.qbx_core:GetPlayer', function()
  RESET_STUB(); STUB.started = { qbx_core = true }
  local bal = 5000
  local fakePlayer = {
    PlayerData = { citizenid = 'ABC123', charinfo = { firstname = 'Sam', lastname = 'Rider' },
                   job = { name = 'roxwoodracing', grade = { level = 2 }, isboss = false } },
    Functions = {
      AddMoney = function(mtype, amount) bal = bal + amount; return true end,
      RemoveMoney = function(mtype, amount) if bal < amount then return false end bal = bal - amount; return true end,
      GetMoney = function(mtype) return bal end,
    },
  }
  STUB.exports = { qbx_core = { GetPlayer = function(_, src) return src == 7 and fakePlayer or nil end } }
  loadBridge()
  EQ(Bridge.GetPlayerIdentifier(7), 'ABC123')
  EQ(Bridge.GetPlayerName(7), 'Sam Rider')
  local f, l = Bridge.GetPlayerFirstLast(7); EQ(f, 'Sam'); EQ(l, 'Rider')
  TRUTHY(Bridge.RemoveMoney(7, 'cash', 1000, 'test')); EQ(Bridge.GetMoney(7, 'cash'), 4000)
  FALSY(Bridge.RemoveMoney(7, 'cash', 99999, 'test'))
  TRUTHY(Bridge.AddMoney(7, 'cash', 10, 'test')); EQ(bal, 4010)
  EQ(Bridge.GetJob(7).name, 'roxwoodracing'); EQ(Bridge.GetJob(7).grade, 2)
  TRUTHY(Bridge.HasJob(7, 'roxwoodracing', 2)); FALSY(Bridge.HasJob(7, 'roxwoodracing', 3)); FALSY(Bridge.HasJob(7, 'police', 0))
  FALSY(Bridge.GetPlayerIdentifier(8), 'offline player')
end)

TEST('no framework -> nil framework and safe returns', function()
  RESET_STUB()
  loadBridge()
  EQ(Bridge.Framework, nil)
  EQ(Bridge.GetPlayerIdentifier(1), nil)
  EQ(Bridge.GetMoney(1, 'cash'), 0)
  FALSY(Bridge.HasJob(1, 'roxwoodracing', 0))
end)
