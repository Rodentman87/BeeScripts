-- beehomeui.lua  ->  install to /lib/beehomeui.lua
-- The home screen: Population down the left with Attention and Recent
-- under it, the meadow and the hive and the wiring down the right.
-- beehome owns what the buttons do; this owns where everything sits.
--
-- Rows: 1 header, 2 totals, 3..H-3 panes, H control bar.
-- Left:  Population (20), Attention (9), Recent (the rest).
-- Right: Meadow (the rest), Hive (9), wiring and caches (10).

local core     = require("beeui")
local config   = require("beeconfig")
local frame    = require("beeframe")
local segs     = require("beesegs")
local colors   = require("beecolors")
local swarm    = require("beeswarm")
local recent   = require("beerecent")
local C, g = core.C, core.g

local ui = {}

local G, W, H = {}, 160, 50

local TITLES = {pop = "Population", att = "Attention", recent = "Recent",
                meadow = "Meadow", hive = "Hive"}

local function geometry()
  W, H = core.size()
  local LW = math.min(frame.DIV - 1, math.floor(W / 2) - 1)
  local RX, RW = LW + 2, W - LW - 1
  local top, bottom = 3, H - 3
  local attH = math.min(9, math.max(4, math.floor((bottom - top + 1) / 5)))
  local popH = math.floor((bottom - top + 1 - attH) * 5 / 9 + 0.5)
  G.div = LW + 1
  G.pop    = {x = 1, y = top, w = LW, h = popH}
  G.att    = {x = 1, y = top + popH, w = LW, h = attH}
  G.recent = {x = 1, y = top + popH + attH, w = LW,
              h = bottom - (top + popH + attH) + 1}
  G.hive   = {x = RX, y = bottom - 18, w = RW, h = 9}
  G.wiring = {x = RX, y = bottom - 9, w = RW, h = 10}
  G.meadow = {x = RX, y = top, w = RW, h = G.hive.y - top}
  G.btnRow = H
end

function ui.geo() return G end

--------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------
function ui.init(status)
  core.begin()
  geometry()
  segs.reset()
  if not core.hasGpu then return end
  frame.header("Library", frame.statusItems(status))
  for k, P in pairs(G) do
    if type(P) == "table" then core.panel(P.x, P.y, P.w, P.h, TITLES[k]) end
  end
  core.panel(G.wiring.x, G.wiring.y, G.wiring.w, G.wiring.h,
             g("wire") .. " " .. g("route"))
  frame.divider(G.div, 3, H - 3)
  swarm.init(G.meadow)
  recent.init(G.recent)
  core.text(G.pop.x + 16, G.pop.y + 1, g("princess"), C.dim)
  core.text(G.pop.x + 22, G.pop.y + 1, g("drone"), C.dim)
end

function ui.header(status) frame.header("Library", frame.statusItems(status)) end

function ui.totals(list) segs.set(2, list, W) end

--------------------------------------------------------------------
-- Population: name, counts, floor mark, a bar scaled to the biggest
-- bank, and a BREED button on anything under its floor.
--------------------------------------------------------------------
local MARK = {low = {"triD", C.bad}, surplus = {"triU", C.good}}

function ui.population(rows, totals, onBreed)
  if not core.hasGpu then return end
  local P = G.pop
  -- Row 1 of the interior is the header, and the last is left for
  -- "+N more", so the species get everything between.
  local room = P.h - 4
  local barX, barW = P.x + 29, math.max(6, P.w - 51)
  for i = 1, room do
    local r = rows[i]
    local y = P.y + 1 + i
    segs.set(y, r and {{text = core.clip(r.species, 13), species = r.species}}
             or {}, P.w - 2, P.x + 1)
    if r then
      core.text(P.x + 16, y, ("%2d"):format(r.p), r.state == "low" and C.bad or C.text)
      core.text(P.x + 20, y, ("%4d"):format(r.d), r.state == "low" and C.bad or C.text)
      local mark = MARK[r.state]
      if mark then core.text(P.x + 26, y, g(mark[1]), mark[2]) end
      local filled = math.floor(barW * r.total / totals.most + 0.5)
      core.fillRect(barX, y, filled, 1, colors.of(r.species))
      core.fillRect(barX + filled, y, barW - filled, 1, C.barEmpty)
      if r.state == "low" and onBreed then
        core.button{id = "breed" .. i, x = P.x + 65, y = y,
                    label = "[ " .. g("play") .. " BREED ]",
                    bg = C.warn, fg = C.headerFg,
                    onPress = function() onBreed(r.species) end}
      end
    end
  end
  segs.set(P.y + P.h - 2, #rows > room
           and {{text = ("  +%d more species"):format(#rows - room),
                 color = C.dim2}} or {}, P.w - 2, P.x + 1)
end

--------------------------------------------------------------------
-- Attention: one line per thing that would stop or slow a run
--------------------------------------------------------------------
function ui.attention(list, onAction)
  if not core.hasGpu then return end
  local P = G.att
  local room = P.h - 3       -- the last inner row is the overflow line
  for i = 1, room do
    local e = list[i]
    local y = P.y + i
    if e then
      local row = {{text = e.icon .. " ", color = e.color}}
      for _, s in ipairs(e.segs) do row[#row + 1] = s end
      segs.set(y, row, P.w - 2, P.x + 1)
      if e.action and onAction then
        core.button{id = "att" .. i, x = P.x + 63, y = y, label = e.label,
                    bg = C.warn, fg = C.headerFg,
                    onPress = function() onAction(e.action) end}
      end
    else
      segs.set(y, {}, P.w - 2, P.x + 1)
    end
  end
  segs.set(P.y + P.h - 2, #list > room
           and {{text = ("  +%d more"):format(#list - room), color = C.dim2}}
           or {}, P.w - 2, P.x + 1)
end

-- Recent lives in beerecent, which owns the ring buffer; entries
-- survive every redraw and every trip through a sub-screen.
ui.log      = recent.add
ui.scroll   = recent.scroll
ui.drawLog  = recent.draw

function ui.meadow(tally, order)
  swarm.reset(tally, order)
  swarm.ground()
end

--------------------------------------------------------------------
-- The control bar. A button only ever NAMES what it wants; beehome
-- decides when to act on it, so nothing long-running starts from
-- inside a touch callback while the screen is still being painted.
-- AUTO-TEND is the exception: it flips a flag and repaints itself.
--------------------------------------------------------------------
function ui.controlBar(want)
  local list = {
    {id = "breed", label = "[ " .. g("play") .. " BREED... ]",
     bg = C.good, fg = C.headerFg},
    {id = "restock", label = "[ " .. g("plus") .. " RESTOCK LOW ]",
     bg = C.warn, fg = C.headerFg},
    {id = "tend", label = ("[ %s AUTO-TEND: %s ]"):format(g("pure"),
     config.autoTend and "ON " or "OFF"),
     bg = config.autoTend and C.good or nil,
     fg = config.autoTend and C.headerFg or nil},
    {id = "settings", label = "[ " .. g("bot") .. " SETTINGS ]"},
    {id = "wiring", label = "[ " .. g("wire") .. " WIRING ]"},
    {id = "rescan", label = "[ " .. g("rescan") .. " RESCAN ]"},
    {id = "update", label = "[ " .. g("update") .. " UPDATE ]"},
    {id = "shell", label = "[ " .. g("shell") .. " SHELL ]"},
  }
  for _, b in ipairs(list) do
    local id = b.id
    b.onPress = function()
      if id == "tend" then
        config.autoTend = not config.autoTend
        ui.controlBar(want)
      else
        want(id)
      end
    end
  end
  frame.bar(G.btnRow, list)
  frame.hint("shell")
end

-- One animation tick: the meadow flies, glint rows shimmer
function ui.tick()
  if not core.hasGpu then return end
  swarm.tick()
  segs.tick()
end

return ui
