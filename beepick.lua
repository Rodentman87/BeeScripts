-- beepick.lua  ->  install to /lib/beepick.lua
-- What the breed screen offers: every mutation both of whose parents
-- are already in the cabinets, the species one further step out, and
-- how far away anything else is. Pure -- the same mutation cache the
-- planner reads, plus the tally, and nothing else.

local stock   = require("beestock")
local planner = require("beeplanner")
local climate = require("beeclimate")

local pick = {}

-- "Owned" is EXISTS, the planner's own definition: some bee actively
-- expresses the species. Not the purity-checked count -- a hybrid is
-- a perfectly good parent, and the planner has always thought so.
function pick.owned(tally)
  local out = {}
  for sp, e in pairs(tally or {}) do
    if #e.princesses + #e.drones > 0 then out[sp] = true end
  end
  return out
end

--------------------------------------------------------------------
-- Seasons. Best effort and never fatal: nil means "not a seasonal
-- mutation", true means it is in season now, false means it is not
-- (including "seasonal in some way we could not read", because a row
-- we cannot vouch for should not offer a button that wastes a queen).
--------------------------------------------------------------------
local MONTHS = {jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
                jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12}
local HOLIDAY = {christmas = 12, halloween = 10, ["new year"] = 1, easter = 0}
local CONTEXT = {"during", "month", "season", "only in", "between", "date"}

local function monthNow()
  return tonumber(os.date("%m"))
end

function pick.season(cond)
  if not cond or cond == "" then return nil end
  local ok, res = pcall(function()
    local s = cond:lower()
    -- An explicit MM-DD range wins, and may wrap the new year
    local m1, d1, m2, d2 = s:match("(%d%d)-(%d%d)%D+(%d%d)-(%d%d)")
    if m1 then
      local now = monthNow() * 100 + tonumber(os.date("%d"))
      local a = tonumber(m1) * 100 + tonumber(d1)
      local b = tonumber(m2) * 100 + tonumber(d2)
      if a <= b then return now >= a and now <= b end
      return now >= a or now <= b
    end
    for name, m in pairs(HOLIDAY) do
      if s:find(name, 1, true) then
        return m > 0 and (monthNow() == m) or false
      end
    end
    -- A bare month name is only a month when something around it says
    -- so: "may" is a verb far more often than it is May.
    local seasonal = false
    for _, word in ipairs(CONTEXT) do
      if s:find(word, 1, true) then seasonal = true end
    end
    if not seasonal then return nil end
    for name, m in pairs(MONTHS) do
      if s:find("%f[%a]" .. name .. "%f[%A]") then return monthNow() == m end
    end
    return false
  end)
  return ok and res or nil
end

--------------------------------------------------------------------
-- One step away: both parents in hand, the result not. One row per
-- result -- if two mutations make the same bee, the better odds win.
--------------------------------------------------------------------
function pick.oneStep(muts, owned, tally)
  local best = {}
  for _, m in ipairs(muts or {}) do
    if owned[m.a] and owned[m.b] and not owned[m.r] then
      local e = best[m.r]
      if not e or m.chance > e.chance then
        local function low(sp)
          local t = tally and tally[sp]
          return (t and stock.state(t) == "low") or false
        end
        best[m.r] = {result = m.r, a = m.a, b = m.b, chance = m.chance,
                     cond = m.cond, season = pick.season(m.cond),
                     lowA = low(m.a), lowB = low(m.b),
                     expCycles = math.ceil(100 / math.max(m.chance, 0.01))}
      end
    end
  end
  local out = {}
  for _, e in pairs(best) do out[#out + 1] = e end
  table.sort(out, function(x, y)
    if x.chance ~= y.chance then return x.chance > y.chance end
    return x.result < y.result
  end)
  return out
end

-- Two steps: one parent in hand (or already a one-step result) and
-- the other a one-step result. No planner calls -- this is a glance
-- at what opens up next, not a route.
function pick.twoStep(muts, owned, oneStep)
  local near = {}
  for _, c in ipairs(oneStep or {}) do near[c.result] = true end
  local out, seen = {}, {}
  for _, m in ipairs(muts or {}) do
    local haveA, haveB = owned[m.a] or near[m.a], owned[m.b] or near[m.b]
    if haveA and haveB and (near[m.a] or near[m.b])
       and not owned[m.r] and not near[m.r] and not seen[m.r] then
      seen[m.r] = true
      out[#out + 1] = m.r
    end
  end
  table.sort(out)
  return out
end

-- How far a species is from here: steps, expected cycles. nil means
-- there is no route from what is in the cabinets right now.
function pick.stepsAway(muts, owned, species)
  if owned[species] then return 0, 0 end
  if not muts then return nil end
  local ok, steps = pcall(planner.compute, muts, owned, species,
                          climate.routeCost)
  if not ok or not steps then return nil end
  local cyc = 0
  for _, s in ipairs(steps) do cyc = cyc + s.expCycles end
  return #steps, cyc, steps
end

-- Counts for the line under the header
function pick.summary(owned, oneStep, twoStep)
  local n, out = 0, 0
  for _ in pairs(owned) do n = n + 1 end
  for _, c in ipairs(oneStep) do
    if c.season == false then out = out + 1 end
  end
  return {owned = n, one = #oneStep, two = #twoStep, offSeason = out}
end

return pick
