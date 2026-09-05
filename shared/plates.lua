Plates = {}

local function san(s)
  if not s then return '' end
  s = tostring(s):gsub('%s+', ''):upper():gsub('[^A-Z0-9]', '')
  return s
end

---@param first string|nil  @param last string|nil  @param fallback string|nil  @param used table|nil
function Plates.FromName(first, last, fallback, used)
  local candidates = {}
  if first or last then
    candidates[#candidates+1] = san((first or '') .. (last or ''))
    candidates[#candidates+1] = san((first and first:sub(1, 1) or '') .. (last or ''))
  end
  candidates[#candidates+1] = san(fallback or '')
  candidates[#candidates+1] = 'RWR'
  local str = 'RWR'
  for _, c in ipairs(candidates) do if #c > 0 then str = c break end end
  if #str > 8 then str = str:sub(1, 8) end
  if used then
    local base, suffix = str, 0
    while used[str] do
      suffix = suffix + 1
      local suf = tostring(suffix)
      str = base:sub(1, math.max(0, 8 - #suf)) .. suf
    end
    used[str] = true
  end
  return str
end
