-- beepanes.lua  ->  install to /lib/beepanes.lua
-- The wide dashboard's bank and chest panes, and the climate row.
-- Geometry comes from beewide (G.bank / G.chest are {x, y, w, h}
-- boxes; content starts one cell inside).
--
-- Bank: drone bars for the step and the final species, a lineage
-- strip (one block per cycle in the queen's species color), stats.
-- Chest: stock by species with proportional bars.

local core    = require("beeui")
local config  = require("beeconfig")
local segs    = require("beesegs")
local colors  = require("beecolors")
local climate = require("beeclimate")
local advice  = require("beeadvice")
local stock   = require("beestock")
local hive    = require("beehive")
local C, g = core.C, core.g

local panes = {}

local G, target
local history = {}                 -- queen species, one per cycle
local cycleN = 0

function panes.init(geo, tgt)
  G, target = geo, tgt
  history, cycleN = {}, 0
end

--------------------------------------------------------------------
-- Bank
--------------------------------------------------------------------
local function droneBar(row, label, species, n, goal)
  local P = G.bank
  local x0 = P.x + 1
  segs.set(row, {{text = label, color = C.dim}, {text = species, species = species},
                 {text = " drones", color = C.dim}}, P.w - 2, x0)
  local bx = x0 + 1 + core.len(label) + core.len(species) + 8
  local barW = 20
  local filled = math.floor(barW * math.min(n, goal) / math.max(goal, 1) + 0.5)
  if filled == barW and n < goal then filled = barW - 1 end
  core.fillRect(bx, row, filled, 1, colors.of(species))
  core.fillRect(bx + filled, row, barW - filled, 1, C.barEmpty)
  core.text(bx + barW + 1, row, ("%d/%d"):format(n, goal), C.dim)
end

-- nP, nD: chest counts; tgt/goal: the step's drones; sub: its species;
-- finalTgt/finalGoal: the overall target's bank, when sub is not it.
function panes.bank(nP, nD, tgt, goal, sub, finalTgt, finalGoal)
  if not (G and core.hasGpu) then return end
  local P = G.bank
  droneBar(P.y + 1, "Step   ", sub or target, tgt or 0, goal or 1)
  if finalTgt then
    droneBar(P.y + 2, "Final  ", target, finalTgt, finalGoal or config.droneGoal)
  else
    segs.set(P.y + 2, {}, P.w - 2, P.x + 1)
  end
  local avg = hive.avgCycle()
  core.line(P.y + 4, ("%d princesses %s %d drones %s cycle %d%s"):format(
            nP, g("mid"), nD, g("mid"), cycleN,
            avg and ("  %s  avg cycle %s"):format(g("mid"), hive.mmss(avg)) or ""),
            C.dim2, P.w - 2, P.x + 1)
end

-- Record the queen's species for this cycle and redraw the strip
function panes.lineage(species, cycle)
  if not (G and core.hasGpu) then return end
  local P = G.bank
  cycleN = cycle or cycleN
  if species then
    history[#history + 1] = species
    while #history > P.w - 2 - 10 do table.remove(history, 1) end
  end
  local list = {{text = "Lineage  ", color = C.dim}}
  for _, sp in ipairs(history) do list[#list + 1] = {text = g("block"), species = sp} end
  segs.set(P.y + 3, list, P.w - 2, P.x + 1)
end

--------------------------------------------------------------------
-- Chest stock
--------------------------------------------------------------------
-- Rows are marked with the floor state: under it, over it, or exactly
-- on it (nothing). Same tally the stock gate runs on, so what the
-- pane says and what the engine does can never drift apart.
local MARK = {low = {"triD", C.bad}, surplus = {"triU", C.good}}

function panes.stock(princesses, drones)
  if not (G and core.hasGpu) then return end
  local P = G.chest
  local tally, order = stock.tally(princesses, drones)
  local rows, most = P.h - 3, 1
  for _, sp in ipairs(order) do most = math.max(most, tally[sp].p + tally[sp].d) end
  local x0, barX, barW = P.x + 1, P.x + 15, 28
  for i = 1, rows do
    local sp = order[i]
    local row = P.y + i
    if sp and (i < rows or #order == rows) then
      local t = tally[sp]
      segs.set(row, {{text = core.clip(sp, 12), species = sp}}, P.w - 2, x0)
      local filled = math.floor(barW * (t.p + t.d) / most + 0.5)
      core.fillRect(barX, row, filled, 1, colors.of(sp))
      core.text(barX + barW + 2, row, ("%3d  %dP %dD"):format(t.p + t.d, t.p, t.d), C.dim)
      -- One cell between the name and the bar, where nothing else goes
      local mark = MARK[stock.state(t)]
      if mark then core.text(barX - 1, row, g(mark[1]), mark[2]) end
    elseif sp then
      segs.set(row, {{text = ("+%d more species"):format(#order - rows + 1),
                      color = C.dim2}}, P.w - 2, x0)
    else
      segs.set(row, {}, P.w - 2, x0)
    end
  end
  local nD = 0
  for _, b in ipairs(drones) do nD = nD + (b.size or 1) end
  core.line(P.y + P.h - 2, ("%d princesses %s %d drones in %d slots"):format(
            #princesses, g("mid"), nD, #princesses + #drones), C.dim2, P.w - 2, x0)
end

--------------------------------------------------------------------
-- Climate row (same wording as the compact dashboard)
--------------------------------------------------------------------
function panes.climate(st, row)
  local bad = st and not st.ok
  core.line(row, bad and (advice.line(st) .. " -- " .. advice.fix(st))
            or ("Climate: " .. climate.apiary().text ..
                (st and (" -- " .. st.species .. " is at home here") or "")),
            bad and C.bad or C.dim)
end

return panes
