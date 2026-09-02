-- beewide.lua  ->  install to /lib/beewide.lua
-- The 160x50 dashboard (any screen 120 columns or wider). Two panes
-- split down the middle. This file owns the frame, the header icon
-- strip, the status row and the control bar, and forwards the rest:
-- beeroute (tree + pedigree), beecross (Punnett square), beehive
-- (queen, bee, timing), beepanes (bank, chest, climate), beelog.
--
-- Rows: 1 header, 2 status, 3..H-3 panes, H-2 climate, H control bar.
-- Left:  Route (tall), This cross (13), Chest (7).
-- Right: Hive (7), Bank (6), Log (the rest).

local core     = require("beeui")
local config   = require("beeconfig")
local segs     = require("beesegs")
local route    = require("beeroute")
local cross    = require("beecross")
local hive     = require("beehive")
local panes    = require("beepanes")
local log      = require("beelog")
local climate  = require("beeclimate")
local computer = require("computer")
local C, g = core.C, core.g

local ui = {hasGpu = core.hasGpu}

local W, H = 160, 50
local G = {}                       -- pane geometry, see geometry()
local target, hasPlanner = "", false
local startTime, cycleN, climateOk = 0, 0, true
local paused, flap = false, false

local TITLES = {route = "Route", cross = "This cross", chest = "Chest",
                hive = "Hive", bank = "Bank", log = "Log"}

local function geometry()
  W, H = core.size()
  local LW = math.floor(W / 2) - 1           -- left pane width
  local RX, RW = LW + 2, W - LW - 1          -- right pane origin, width
  local top, bottom = 3, H - 3
  local routeH = (bottom - top + 1) - 13 - 7
  G.div   = LW + 1
  G.route = {x = 1, y = top, w = LW, h = routeH}
  G.cross = {x = 1, y = top + routeH, w = LW, h = 13}
  G.chest = {x = 1, y = top + routeH + 13, w = LW, h = 7}
  G.hive  = {x = RX, y = top, w = RW, h = 7}
  G.bank  = {x = RX, y = top + 7, w = RW, h = 6}
  G.log   = {x = RX, y = top + 13, w = RW, h = bottom - (top + 13) + 1}
  G.climateRow, G.btnRow = H - 2, H
end

local function runTime()
  local s = math.floor(computer.uptime() - startTime)
  local h, m = math.floor(s / 3600), math.floor((s % 3600) / 60)
  return h > 0 and ("%dh%02dm"):format(h, m) or ("%dm"):format(m)
end

--------------------------------------------------------------------
-- Header: title left, icon strip right. Bright = on, dim = off.
--------------------------------------------------------------------
local function drawHeader()
  core.fillRect(1, 1, W, 1, C.header)
  local title = "BeeBreeder " .. g("right") .. " "
  core.text(2, 1, title, C.headerFg, C.header)
  core.text(2 + core.len(title), 1, target, C.headerFg, C.header)
  local items = {
    {g("route") .. " route", hasPlanner},
    {g("chat") .. " chat", config.chatEveryQueen},
    {g("bot") .. " bot", config.botEnabled},
    {g("pure") .. " pure", config.requirePure},
    {g("temp") .. " " .. climate.apiary().text .. " " ..
       g(climateOk and "check" or "warn"), climateOk},
    {("cycle %d  %s"):format(cycleN, runTime()), true},
  }
  local total = 0
  for _, it in ipairs(items) do total = total + core.len(it[1]) + 3 end
  local x = W - total
  for _, it in ipairs(items) do
    core.text(x, 1, it[1], it[2] and C.headerFg or C.dim2, C.header)
    x = x + core.len(it[1]) + 3
  end
end

--------------------------------------------------------------------
-- Control bar
--------------------------------------------------------------------
local function drawButtons()
  local y = G.btnRow
  core.fillRect(1, y, W, 1)
  local x = 2
  local function btn(id, label, bg, fg, fn)
    core.button{id = id, x = x, y = y, label = label, bg = bg, fg = fg, onPress = fn}
    x = x + core.len(label) + 2
  end
  local function toggle(id, glyph, name, on, fn)
    btn(id, ("[ %s %s: %s ]"):format(g(glyph), name, on and "ON " or "OFF"),
        on and C.good or C.barEmpty, on and C.headerFg or C.text,
        function() fn() drawButtons() drawHeader() end)
  end
  btn("halt", "[ " .. g("halt") .. " HALT ]", C.bad, C.text, core.halt)
  btn("pause", paused and ("[ " .. g("right") .. " RESUME ]")
                      or ("[ " .. g("pause") .. " PAUSE ]"),
      paused and C.warn or C.barEmpty, paused and C.headerFg or C.text,
      function() paused = not paused drawButtons() end)
  toggle("chat", "chat", "CHAT", config.chatEveryQueen,
         function() config.chatEveryQueen = not config.chatEveryQueen end)
  toggle("pure", "pure", "PURE", config.requirePure,
         function() config.requirePure = not config.requirePure end)
  btn("gminus", "[ - ]", C.barEmpty, nil, function()
    config.droneGoal = math.max(1, config.droneGoal - 1) drawButtons() end)
  local goal = ("goal %d"):format(config.droneGoal)
  core.text(x, y, goal, C.text)
  x = x + core.len(goal) + 2
  btn("gplus", "[ + ]", C.barEmpty, nil, function()
    config.droneGoal = config.droneGoal + 1 drawButtons() end)
  btn("logup", "[ LOG " .. g("triU") .. " ]", C.barEmpty, nil, function() log.scroll(1) end)
  btn("logdn", "[ LOG " .. g("triD") .. " ]", C.barEmpty, nil, function() log.scroll(-1) end)
  core.text(W - 8, y, "Q halts", C.dim2)
end

--------------------------------------------------------------------
-- Public API (what beedash forwards)
--------------------------------------------------------------------
function ui.init(tgt, muts)
  core.begin()
  geometry()
  target, hasPlanner = tgt, muts ~= nil
  startTime, cycleN, climateOk = computer.uptime(), 0, true
  paused = false
  segs.reset()
  if not core.hasGpu then return end
  drawHeader()
  for k, P in pairs(G) do
    if type(P) == "table" then core.panel(P.x, P.y, P.w, P.h, TITLES[k]) end
  end
  for y = 3, H - 3 do core.text(G.div, y, g("v"), C.dim2) end
  route.init(G.route)
  cross.init(G.cross, muts)
  hive.init(G.hive)
  panes.init(G, tgt)
  log.init(G.log)
  drawButtons()
end

function ui.status(text)
  segs.set(2, {{text = "Status: ", color = C.dim}, {text = text}}, W)
end

function ui.cycle(n) cycleN = n drawHeader() end

function ui.pair(p, d, stepInfo, sub)
  hive.pair(p, d)
  panes.lineage(p.active, cycleN)
  cross.show(p, d, sub or target)
end

function ui.route(r) route.show(r, target, hive.avgCycle()) end
function ui.chest(...) panes.bank(...) end
function ui.stock(...) panes.stock(...) end
function ui.queenStart() hive.queenStart() end
function ui.queenDone() hive.queenDone() end
function ui.pauseRequested() return paused end

function ui.climate(st)
  climateOk = not (st and not st.ok)
  panes.climate(st, G.climateRow)
  drawHeader()
end

function ui.log(text, kind)
  if not core.hasGpu then print(text) return end
  log.add(text, (kind == "good" and C.good) or (kind == "warn" and C.warn)
                or (kind == "bad" and C.bad) or C.text)
end

-- One spinner tick: shimmer, the bee on its bar, the pedigree pulse
function ui.buzz()
  if not core.hasGpu then return end
  segs.tick()
  flap = not flap
  hive.tick(route.current())
  route.tick(flap)
end

function ui.banner(text)
  if not core.hasGpu then print(text) return end
  core.fillRect(1, 2, W, 1, C.good)
  core.text(2, 2, core.clip(text), C.headerFg, C.good)
  core.cursorBottom()
end

ui.done          = core.finish
ui.sleep         = core.sleep
ui.haltRequested = core.haltRequested

return ui
