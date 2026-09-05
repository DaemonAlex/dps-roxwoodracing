-- Society money. Renewed-Banking is the DPS backend; qb-banking is the fallback; 'none' means
-- fees/purses become plain player cash (spec section 4) and a warning is printed at boot.
Banking = {}
Banking.Provider = 'none'
if GetResourceState('Renewed-Banking') == 'started' or GetResourceState('Renewed-Banking') == 'starting' then
  Banking.Provider = 'Renewed-Banking'
elseif GetResourceState('qb-banking') == 'started' then
  Banking.Provider = 'qb-banking'
end
print(('[dps-roxwoodracing] banking: %s'):format(Banking.Provider))
if Banking.Provider == 'none' then
  print('[dps-roxwoodracing] WARNING: no society banking found; entry fees and purses fall back to player cash')
end

local function rb() return exports['Renewed-Banking'] end

function Banking.EnsureAccount(name, label)
  if Banking.Provider == 'Renewed-Banking' then
    local ok, res = pcall(function() return rb():CreateJobAccount({ name = name, label = label }, 0) end)
    if not ok then print('[dps-roxwoodracing] CreateJobAccount failed: ' .. tostring(res)) end
    return ok and res ~= nil
  elseif Banking.Provider == 'qb-banking' then
    pcall(function() exports['qb-banking']:CreateJobAccount(name, 0) end)
    return true
  end
  return true
end

function Banking.GetBalance(account)
  if Banking.Provider == 'Renewed-Banking' then
    local ok, v = pcall(function() return rb():getAccountMoney(account) end)
    return ok and tonumber(v) or 0
  elseif Banking.Provider == 'qb-banking' then
    local ok, v = pcall(function() return exports['qb-banking']:GetAccountBalance(account) end)
    return ok and tonumber(v) or 0
  end
  return 1e12 -- no ledger: never "short"
end

local function ledger(account, title, amount, message, issuer, receiver, ttype)
  if Banking.Provider ~= 'Renewed-Banking' then return end
  pcall(function() rb():handleTransaction(account, title, amount, message, issuer, receiver, ttype) end)
end

function Banking.Deposit(account, amount, title, message, fromLabel)
  if amount <= 0 then return true end
  if Banking.Provider == 'Renewed-Banking' then
    local ok, res = pcall(function() return rb():addAccountMoney(account, amount) end)
    if not (ok and res) then return false end
    ledger(account, title, amount, message, fromLabel or 'Player', account, 'deposit')
    return true
  elseif Banking.Provider == 'qb-banking' then
    local ok, res = pcall(function() return exports['qb-banking']:AddMoney(account, amount, title) end)
    return ok and res ~= false
  end
  return true
end

function Banking.Withdraw(account, amount, title, message, toLabel)
  if amount <= 0 then return true end
  if Banking.Provider == 'Renewed-Banking' then
    if Banking.GetBalance(account) < amount then return false end
    local ok, res = pcall(function() return rb():removeAccountMoney(account, amount) end)
    if not (ok and res) then return false end
    ledger(account, title, amount, message, account, toLabel or 'Player', 'withdraw')
    return true
  elseif Banking.Provider == 'qb-banking' then
    if Banking.GetBalance(account) < amount then return false end
    local ok, res = pcall(function() return exports['qb-banking']:RemoveMoney(account, amount, title) end)
    return ok and res ~= false
  end
  return true
end

-- House mode: money is minted for the player but the ledger still shows the payment.
function Banking.LogOnly(account, amount, title, message, fromLabel, toLabel)
  ledger(account, title, amount, message, fromLabel or account, toLabel or 'Player', 'withdraw')
end
