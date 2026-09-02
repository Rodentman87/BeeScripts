-- beebrief.lua  ->  install to /lib/beebrief.lua
-- The breed screen's Preview pane: what breeding the selected species
-- would actually involve. The route as the dashboard's indented tree,
-- the restocking that has to happen first, the recipe pair, the
-- conditions, a total, and the dot pedigree if there is room left.
--
-- Everything above the pedigree is segment rows, so it costs nothing
-- to rebuild on every keystroke while the search list is scrolling.

local core    = require("beeui")
local segs    = require("beesegs")
local tree    = require("beetree")
local ped     = require("beepedigree")
local stock   = require("beestock")
local found   = require("beefound")
local climate = require("beeclimate")
local advice  = require("beeadvice")
local C, g = core.C, core.g

local brief = {}

local function counts(sp, tally)
  local e = tally and tally[sp]
  if not e then return nil end
  local out = {{text = ("  %d%s %d%s"):format(e.p, g("princess"), e.d, g("drone")),
                color = C.dim}}
  if stock.state(e) == "low" then
    out[#out + 1] = {text = " " .. g("triD"), color = C.bad}
  end
  return out
end

-- The plan as a tree, with what we actually hold written beside each
-- species that is already in the cabinets.
local function treeRows(steps, owned, tally)
  local root = tree.build(steps, owned, nil)
  if not root then return {}, nil end
  local out = {}
  for _, r in ipairs(tree.rows(root, {})) do
    local list = r.segs
    if r.node and r.node.state == "have" then
      for _, s in ipairs(counts(r.node.sp, tally) or {}) do
        list[#list + 1] = s
      end
    end
    out[#out + 1] = list
  end
  return out, root
end

-- What the stock gate would insist on before the recipe can run
local function restockRows(steps, tally)
  local rows, seen, cycles = {}, {}, 0
  for _, s in ipairs(steps) do
    for _, sp in ipairs({s.a, s.b}) do
      if not seen[sp] then
        seen[sp] = true
        for _, l in ipairs(stock.restockPlan(tally or {}, sp)) do
          cycles = cycles + l.cycles
          rows[#rows + 1] = {{text = g("plus") .. " ", color = C.warn},
                             {text = sp, species = sp},
                             {text = (" %s %d %s %d"):format(
                               l.what == "princess" and g("princess") or g("drone"),
                               l.from, g("right"), l.to), color = C.dim},
                             {text = ("        ~%d cyc"):format(l.cycles),
                              color = C.dim2}}
        end
      end
    end
  end
  return rows, cycles
end

-- Climate and foundation, the two things worth sorting out first
local function conditionRow(steps, target)
  local list = {}
  local st = climate.status(target)
  if st and not st.ok then
    list[#list + 1] = {text = advice.line(st), color = C.bad}
  else
    list[#list + 1] = {text = climate.apiary().text .. " " .. g("check"),
                       color = C.text}
  end
  for _, s in ipairs(steps) do
    local block = found.parse(s.cond)
    if block then
      list[#list + 1] = {text = "     " .. g("square") .. " " .. block,
                         color = C.warn}
      break
    end
  end
  return list
end

--------------------------------------------------------------------
-- Draw the whole pane. `sel` is the selected species (nil clears the
-- pane) and `r` is its route record from beepick: {steps, cycles,
-- plan}, where steps nil means there is no route at all and 0 means
-- the species is already in the cabinets.
--------------------------------------------------------------------
function brief.show(P, sel, r, owned, tally, avgCycle)
  if not core.hasGpu then return end
  local ix, iy, iw, ih = P.x + 1, P.y + 1, P.w - 2, P.h - 2
  core.fillRect(ix, iy, iw, ih)
  local rows = {}
  local function blank() rows[#rows + 1] = {} end
  if not sel then
    segs.set(iy, {{text = "Pick a species to see its route.", color = C.dim2}},
             iw, ix)
    return
  end
  if r and r.steps == nil then
    segs.set(iy, {{text = sel, species = sel}}, iw, ix)
    segs.set(iy + 1, {{text = "No route from what is in the cabinets. Breed a",
                       color = C.bad}}, iw, ix)
    segs.set(iy + 2, {{text = "starter species first, or check the spelling.",
                       color = C.dim}}, iw, ix)
    return
  end

  local steps = (r and r.plan) or {}
  local total, root = 0, nil
  for _, s in ipairs(steps) do total = total + s.expCycles end
  rows[#rows + 1] = {{text = sel, species = sel},
    {text = ("      %d step%s  ~%d cyc"):format(#steps,
     #steps == 1 and "" or "s", total), color = C.dim}}

  local body
  body, root = treeRows(steps, owned, tally)
  for _, row in ipairs(body) do rows[#rows + 1] = row end
  if not root then
    rows[#rows + 1] = {{text = "Already in the cabinets", color = C.good},
                       {text = " -- a run just banks drones.", color = C.dim}}
  end

  local restock, extraCycles = restockRows(steps, tally)
  if #restock > 0 then
    blank()
    for _, row in ipairs(restock) do rows[#rows + 1] = row end
    total = total + extraCycles
  end

  local last = steps[#steps]
  if last then
    blank()
    rows[#rows + 1] = {{text = g("play") .. " ", color = C.good},
      {text = last.a, species = last.a}, {text = " " .. g("princess") .. " " ..
       g("times") .. " ", color = C.dim},
      {text = last.b, species = last.b}, {text = " " .. g("drone") .. " " ..
       g("right") .. " ", color = C.dim},
      {text = last.result, species = last.result},
      {text = (" %.0f%%"):format(last.chance), color = C.dim}}
  end
  blank()
  rows[#rows + 1] = conditionRow(steps, sel)
  blank()
  local sum = {{text = g("sigma") .. " ", color = C.dim},
               {text = ("~%d cyc"):format(total)}}
  if avgCycle and avgCycle > 0 then
    sum[#sum + 1] = {text = ("   %s %s ~%dm"):format(g("mid"), g("avg"),
                     math.max(1, math.floor(total * avgCycle / 60))), color = C.dim2}
  end
  rows[#rows + 1] = sum

  for i = 1, ih do
    segs.set(iy + i - 1, rows[i] or {}, iw, ix)
  end

  -- The pedigree gets whatever is left under the text, centered
  if root then
    local lay = ped.layout(root)
    local free = ih - #rows - 1
    if lay.h <= free and lay.w <= iw then
      ped.draw(lay, ix + math.floor((iw - lay.w) / 2),
               iy + ih - lay.h, false, true)
    end
  end
end

return brief
