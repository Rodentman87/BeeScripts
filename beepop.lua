-- beepop.lua  ->  install to /lib/beepop.lua
-- What the home screen knows: the library by species, the totals
-- along the top, and the Attention list -- one line per thing that
-- would stop or slow a run.
--
-- Pure: it is handed the last scan and a table of what only hardware
-- could know (cache age, cabinet fill, apiary state, wiring, climate)
-- and turns them into rows and segment lists. Nothing here touches
-- the transposer, and nothing here draws.

local core  = require("beeui")
local stock = require("beestock")
local C, g = core.C, core.g

local pop = {}

-- The species with the most princesses to spare: whoever pays for a
-- conversion when a species has no princess of its own left.
function pop.donor(tally)
  local pf = stock.floors()
  local best, bestSpare
  for sp, e in pairs(tally) do
    local spare = e.p - pf
    if spare > 0 and (not bestSpare or spare > bestSpare
                      or (spare == bestSpare and sp < best)) then
      best, bestSpare = sp, spare
    end
  end
  return best
end

local function shortfall(e)
  local pf, df = stock.floors()
  if e.p < pf then return pf - e.p, "princess" end
  return df - e.d, "drone"
end

-- One entry per thing worth a look: {icon, color, segs, action, label}.
-- `action` is what the button on that line does -- "restock <Species>"
-- or "rebuild" -- and nil for the lines that are just information.
function pop.attention(tally, rows, extra)
  local out = {}
  local pf = stock.floors()
  for _, r in ipairs(rows) do
    if r.state == "low" then
      local e = tally[r.species]
      local list = {{text = r.species, species = r.species},
                    {text = ("  %d%s %d%s  "):format(r.p, g("princess"),
                                                     r.d, g("drone"))}}
      if e.p < pf then
        -- No princess of her own left: it takes a conversion, and the
        -- princess that pays for it is worth naming.
        list[#list + 1] = {text = g("triD") .. " " .. g("princess") .. " " ..
                                  g("mid") .. " ", color = C.bad}
        local donor = pop.donor(tally)
        if donor then
          list[#list + 1] = {text = donor, species = donor}
          list[#list + 1] = {text = " " .. g("smallR") .. " ", color = C.dim}
          list[#list + 1] = {text = r.species, species = r.species}
        else
          list[#list + 1] = {text = "no princess to spare", color = C.bad}
        end
      else
        local n, kind = shortfall(e)
        list[#list + 1] = {text = ("%s %d%s"):format(g("triD"), n, g(kind)),
                           color = C.bad}
      end
      out[#out + 1] = {icon = g("warn"), color = C.bad, segs = list,
                       action = "restock " .. r.species,
                       label = "[ " .. g("play") .. " RESTOCK ]"}
    end
  end

  local cache = extra.cache
  out[#out + 1] = {icon = g("route"), color = cache and C.warn or C.bad,
                   segs = {{text = cache and cache.age or "no mutation cache",
                            color = cache and C.dim or C.bad}},
                   action = (not cache or cache.stale) and "rebuild" or nil,
                   label = "[ " .. g("rescan") .. " REBUILD ]"}
  if extra.fill then
    out[#out + 1] = {icon = g("cabinet"), color = C.dim,
                     segs = {{text = extra.fill, color = C.dim}}}
  end
  if extra.apiary then
    out[#out + 1] = {icon = g("apiary"), color = C.dim,
                     segs = {{text = extra.apiary, color = C.dim}}}
  end
  local wired = extra.sidesOk ~= false
  out[#out + 1] = {icon = g(wired and "check" or "warn"),
                   color = wired and C.good or C.bad,
                   segs = {{text = g("wire") .. " " .. g("mid") .. " " ..
                            tostring(extra.climate or "climate unknown"),
                            color = C.dim}}}
  return out
end

--------------------------------------------------------------------
-- rows: one per species, low first, then the biggest banks.
-- totals: {species, p, d, low, most} -- `most` scales the bars.
-- Returns rows, totals, attention, tally, order.
--------------------------------------------------------------------
function pop.build(princesses, drones, extra)
  extra = extra or {}
  local tally, order = stock.tally(princesses, drones)
  local rows = {}
  local totals = {species = 0, p = 0, d = 0, low = 0, most = 1}
  for _, sp in ipairs(order) do
    local e = tally[sp]
    local state = stock.state(e)
    rows[#rows + 1] = {species = sp, p = e.p, d = e.d, state = state,
                       total = e.p + e.d}
    totals.species = totals.species + 1
    totals.p = totals.p + e.p
    totals.d = totals.d + e.d
    if state == "low" then totals.low = totals.low + 1 end
    if e.p + e.d > totals.most then totals.most = e.p + e.d end
  end
  return rows, totals, pop.attention(tally, rows, extra), tally, order
end

-- The row of totals under the header
function pop.totalsSegs(totals, extra)
  extra = extra or {}
  local list = {{text = ("%d species %s %d%s %s %d%s"):format(
    totals.species, g("mid"), totals.p, g("princess"), g("mid"),
    totals.d, g("drone"))}}
  if totals.low > 0 then
    list[#list + 1] = {text = "     " .. g("triD") .. " " .. totals.low,
                       color = C.bad}
  end
  if extra.apiary then
    list[#list + 1] = {text = "     " .. g("apiary") .. " " .. extra.apiary,
                       color = C.dim}
  end
  if extra.nextScan then
    list[#list + 1] = {text = "     " .. g("rescan") .. " " .. extra.nextScan,
                       color = C.dim}
  end
  return list
end

return pop
