local function loadBanking() Config = { Job = { name = 'roxwoodracing', label = 'Roxwood Raceway' } }; Banking = nil; dofile('integrations/banking.lua') end

TEST('Renewed-Banking: deposit/withdraw call the exports and log a transaction', function()
  RESET_STUB(); STUB.started = { ['Renewed-Banking'] = true }
  local bal, log = 2000, {}
  STUB.exports = { ['Renewed-Banking'] = {
    getAccountMoney = function(_, acc) return bal end,
    addAccountMoney = function(_, acc, amt) bal = bal + amt return true end,
    removeAccountMoney = function(_, acc, amt) if bal < amt then return false end bal = bal - amt return true end,
    handleTransaction = function(_, acc, title, amount, message, issuer, receiver, ttype) log[#log+1] = { acc, title, amount, ttype } end,
    CreateJobAccount = function(_, job, initial) return { id = job.name } end,
  } }
  loadBanking()
  EQ(Banking.Provider, 'Renewed-Banking')
  TRUTHY(Banking.EnsureAccount('roxwoodracing', 'Roxwood Raceway'))
  TRUTHY(Banking.Deposit('roxwoodracing', 500, 'Entry fee', 'Lobby X', 'Sam Rider')); EQ(bal, 2500)
  TRUTHY(Banking.Withdraw('roxwoodracing', 1000, 'Purse', '1st place', 'Sam Rider')); EQ(bal, 1500)
  FALSY(Banking.Withdraw('roxwoodracing', 9999, 'Purse', 'too much', 'Sam Rider')); EQ(bal, 1500)
  EQ(#log, 2); EQ(log[1][4], 'deposit'); EQ(log[2][4], 'withdraw')
end)

TEST('no banking: Deposit/Withdraw succeed as no-ops and balance is huge', function()
  RESET_STUB(); loadBanking()
  EQ(Banking.Provider, 'none')
  TRUTHY(Banking.Deposit('roxwoodracing', 5, 't', 'm', 'x'))
  TRUTHY(Banking.Withdraw('roxwoodracing', 5, 't', 'm', 'x'))
  TRUTHY(Banking.GetBalance('roxwoodracing') >= 1e9)
end)

TEST('Garages: jg present -> insert row with garage_id; absent -> garage column', function()
  RESET_STUB(); STUB.started = { ['jg-advancedgarages'] = true }
  Config = { Economy = { prizeGarage = 'Roxwood Raceway' } }
  Bridge = { Framework = 'qbx', GetPlayerIdentifier = function() return 'ABC123' end }
  function GetPlayerIdentifierByType() return 'license:abc' end
  dofile('integrations/garages.lua')
  TRUTHY(Garages.GiveVehicle(7, 'sultan3', 'PRIZE123'))
  TRUTHY(STUB.queries[1].sql:find('garage_id'), 'uses garage_id column')
  EQ(STUB.queries[1].params[7], 'Roxwood Raceway')
  RESET_STUB(); dofile('integrations/garages.lua')
  Garages.GiveVehicle(7, 'sultan3', 'PRIZE123')
  TRUTHY(STUB.queries[1].sql:find('garage,'), 'plain garage column')
end)
