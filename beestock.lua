-- beestock.lua  ->  install to /lib/beestock.lua
-- The stock floor: every species in the library is kept at a floor of
-- princessFloor princesses and droneFloor drones, and everything
-- above that is surplus -- the fuel crosses are allowed to spend.
-- Floors apply to EVERY species present, not only the ones in the
-- current plan, so there is no fuel species and no needs list.
--
-- This file is the bookkeeping: what we have, what counts as low,
-- whether a pair is safe to breed. beebank is what to do about it.
-- Pure logic, no hardware and no screens.
--
-- Two facts shape everything. A princess is never consumed, only
-- transformed, so the only way to lose a species' princess line is to
-- put the last one under a drone of another species. A drone IS
-- consumed. Drones run out; princesses get lost by accident.

local config = require("beeconfig")
local genes  = require("beegenes")

local stock = {}

-- Live from config every call: the settings screen edits these while
-- everything is running.
function stock.floors()
  return config.princessFloor or 1,
         config.droneFloor or config.intermediateDrones or 4
end

-- One entry per ACTIVE species: {species, p, d, princesses, drones}.
-- p and d count the way genes.isWinner counts, so with requirePure on
-- a hybrid does not hold the floor; the lists still keep every bee of
-- that active species, because a hybrid is a usable parent for it.
-- Returns tally, order -- low species first, then the biggest banks.
function stock.tally(princesses, drones)
  local t, order = {}, {}
  local function entry(sp)
    if not t[sp] then
      t[sp] = {species = sp, p = 0, d = 0, princesses = {}, drones = {}}
      order[#order + 1] = sp
    end
    return t[sp]
  end
  local function add(list, kind, into)
    for _, bee in ipairs(list or {}) do
      if bee.active then
        local e = entry(bee.active)
        e[into][#e[into] + 1] = bee
        if genes.isWinner(bee, bee.active) then
          e[kind] = e[kind] + (bee.size or 1)
        end
      end
    end
  end
  add(princesses, "p", "princesses")
  add(drones, "d", "drones")
  table.sort(order, function(a, b)
    local la = stock.state(t[a]) == "low"
    local lb = stock.state(t[b]) == "low"
    if la ~= lb then return la end
    local ta, tb = t[a].p + t[a].d, t[b].p + t[b].d
    if ta ~= tb then return ta > tb end
    return a < b
  end)
  return t, order
end

function stock.state(e)
  local pf, df = stock.floors()
  if e.p < pf or e.d < df then return "low" end
  if e.p > pf or e.d > df then return "surplus" end
  return "ok"
end

-- Is this pair safe to breed as it stands? Returns ok, reason.
function stock.safe(tally, p, d)
  local pf, df = stock.floors()
  -- A queen eats exactly one drone, whatever the stack size.
  local de = tally[d.active]
  if de and (de.d - 1) < df then
    return false, ("spends the last spare %s drone"):format(tostring(d.active))
  end
  -- She survives a cross with her own kind whatever happens; it is
  -- the foreign drone that can turn the last of a line into something
  -- else entirely.
  local pe = tally[p.active]
  if pe and pe.p <= pf and d.active ~= p.active then
    return false, ("spends the last %s princess"):format(tostring(p.active))
  end
  return true
end

-- What it would take to put `species` back on its feet, as preview
-- lines {what=, species=, from=, to=, cycles=}. A princess costs two
-- cycles either way (cross, then her queen); drones come in at the
-- best fertility we can actually see, two when nothing says.
function stock.restockPlan(tally, species)
  local pf, df = stock.floors()
  local e, lines = tally[species], {}
  if not e then return lines end
  if e.p < pf then
    lines[#lines + 1] = {what = "princess", species = species,
                         from = e.p, to = pf, cycles = 2}
  end
  if e.d < df then
    local fert
    for _, dr in ipairs(e.drones) do
      if dr.fertility then fert = math.max(fert or 0, dr.fertility) end
    end
    lines[#lines + 1] = {what = "drones", species = species,
                         from = e.d, to = df,
                         cycles = math.ceil((df - e.d) / math.max(1, fert or 2))}
  end
  return lines
end

-- Every species currently under its floor, in the tally's order.
function stock.low(tally, order)
  local out = {}
  for _, sp in ipairs(order) do
    if stock.state(tally[sp]) == "low" then out[#out + 1] = sp end
  end
  return out
end

return stock
