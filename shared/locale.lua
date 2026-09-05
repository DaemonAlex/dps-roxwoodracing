-- Locale(key, ...) : "{1}" "{2}" substitution; unknown keys return the key itself.
function Locale(key, ...)
  local tbl = Config.LocaleTable or {}
  local str = tbl[key] or key
  local args = { ... }
  return (str:gsub('{(%d+)}', function(n) return tostring(args[tonumber(n)] or '') end))
end
