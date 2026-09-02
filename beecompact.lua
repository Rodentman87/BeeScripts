-- beecompact.lua  ->  install to /lib/beecompact.lua
-- The 80x25 dashboard, built on the beeui core toolkit. beedash picks
-- it for narrow screens (beewide is the 160x50 layout). Species
-- names render in their authentic colors; glint species shimmer.
--    1  header bar
--    2  status  (bee top-right)      3  cycle (bee bottom-right)
--    4  current princess             5  current drone
--    6  chest + drone progress bar
--  7-10 route pane: done / current / next / remainder
--   11  divider                  12-22 scrolling log
--   23  climate line          24  touch buttons: [ HALT ] [ CHAT ]

local core    = require("beeui")
local config  = require("beeconfig")
local colors  = require("beecolors")
local segs    = require("beesegs")
local climate = require("beeclimate")
local advice  = require("beeadvice")
local C = core.C

local ui = { hasGpu = core.hasGpu }

local W, H = 80, 25
local LOG_TOP = 12
local logLines = {}
local curSpecies = nil -- species being bred (tints + shimmers the bee)

local BEE_W = 7
local BEE_FRAMES = {
  {" \\ /  ", "={;;}>"},
  {" | |  ", "={;;}>"},
  {" / \\  ", "={;;}>"},
  {" | |  ", "={;;}>"},
}
local beeFrame = 0

local function logBottom() return H - 3 end
local function btnRow()    return H - 1 end
local function rowWidth(row)
  return (row <= 3) and (W - BEE_W - 2) or W
end

local function setLine(row, text, color)
  core.line(row, text, color, rowWidth(row))
end

--------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------
local function drawButtons()
  core.fillRect(1, btnRow(), W, 1)
  core.button{id = "halt", x = 2, y = btnRow(), label = "[ HALT ]",
              bg = C.bad, fg = C.text,
              onPress = function() core.halt() end}
  local on = config.chatEveryQueen
  core.button{id = "chat", x = 12, y = btnRow(),
              label = on and "[ CHAT: ON  ]" or "[ CHAT: OFF ]",
              bg = on and C.good or C.barEmpty,
              fg = on and C.headerFg or C.text,
              onPress = function()
                config.chatEveryQueen = not config.chatEveryQueen
                drawButtons()
              end}
end

--------------------------------------------------------------------
-- Public drawing API
--------------------------------------------------------------------
function ui.init(target)
  core.begin()
  W, H = core.size()
  logLines, curSpecies = {}, nil
  segs.reset()
  if not core.hasGpu then return end
  core.fillRect(1, 1, W, 1, C.header)
  core.text(2, 1, core.clip("BeeBreeder -> " .. target), C.headerFg, C.header)
  core.hline(11, "Log")
  drawButtons()
end

function ui.status(text)  setLine(2, "Status: " .. text) end
function ui.cycle(n)      setLine(3, "Cycle:  " .. n) end
function ui.princess(bee) segs.set(4, segs.bee("P: ", bee), rowWidth(4)) end
function ui.drone(bee)    segs.set(5, segs.bee("D: ", bee), rowWidth(5)) end
function ui.pair(p, d)    ui.princess(p) ui.drone(d) end

function ui.chest(p, d, tgt, goal)
  local prefix = ("Chest:  %dP %dD  "):format(p, d)
  setLine(6, prefix)
  if not (core.hasGpu and tgt and goal and goal > 0) then return end
  local barW = math.min(20, W - #prefix - 12)
  local filled = math.floor(barW * math.min(tgt, goal) / goal + 0.5)
  -- never render a full bar until the goal is actually met
  if filled == barW and tgt < goal then filled = barW - 1 end
  local x0 = 2 + #prefix
  core.fillRect(x0, 6, filled, 1, C.good)
  core.fillRect(x0 + filled, 6, barW - filled, 1, C.barEmpty)
  core.text(x0 + barW + 1, 6, ("%d/%d"):format(tgt, goal))
end

-- Route pane. r = {done={names}, cur={a,b,r,chance,exp} or {bank,goal},
-- nxt={a,b,r} or nil, tail=string or nil}
function ui.route(r)
  local dsegs = {{text = (#(r.done or {}) > 0) and "Done: " or "Route:",
                  color = C.good}}
  for i, sp in ipairs(r.done or {}) do
    if i > 1 then dsegs[#dsegs + 1] = {text = ", "} end
    dsegs[#dsegs + 1] = {text = sp, species = sp}
  end
  segs.set(7, dsegs)

  local cur = r.cur
  if cur and cur.bank then
    curSpecies = cur.bank
    segs.set(8, {{text = "> bank "}, {text = cur.bank, species = cur.bank},
                 {text = (" to %d %sdrones"):format(cur.goal,
                          config.requirePure and "pure " or "")}})
  elseif cur then
    curSpecies = cur.r
    segs.set(8, segs.cross("> ", cur.a, cur.b, cur.r,
             (" (%.0f%%, ~%d cycles)"):format(cur.chance, cur.exp)))
  else
    curSpecies = nil
    segs.set(8, {})
  end

  if r.nxt then
    segs.set(9, segs.cross("  then: ", r.nxt.a, r.nxt.b, r.nxt.r))
  else
    segs.set(9, {})
  end
  segs.set(10, {{text = r.tail or "", color = C.dim}})
end

-- Climate row: what the hive provides, and -- when the species being
-- bred cannot live there -- both ways out of it. st is a
-- beeclimate.status verdict, or nil when the registry has no say.
function ui.climate(st)
  local bad = st and not st.ok
  if not core.hasGpu then
    if bad then print(advice.line(st)) end
    return
  end
  core.line(H - 2, bad and (advice.line(st) .. " -- " .. advice.fix(st))
            or ("Climate: " .. climate.apiary().text ..
                (st and (" -- " .. st.species .. " is at home here") or "")),
            bad and C.bad or C.dim)
end

-- kind: nil (normal), "good", "warn", "bad"
function ui.log(text, kind)
  if not core.hasGpu then print(text) return end
  local color = C.text
  if kind == "good" then color = C.good
  elseif kind == "warn" then color = C.warn
  elseif kind == "bad" then color = C.bad end
  local maxLines = logBottom() - LOG_TOP + 1
  table.insert(logLines, {text = core.clip(text), color = color})
  while #logLines > maxLines do table.remove(logLines, 1) end
  for i, line in ipairs(logLines) do
    core.line(LOG_TOP + i - 1, line.text, line.color)
  end
end

-- Advance the spinner one wing-flap. The bee wears the color of the
-- species being bred (yellow when idle) and shimmers for glint
-- species, as does every glinting species name on screen.
function ui.buzz()
  if not core.hasGpu then return end
  beeFrame = beeFrame % #BEE_FRAMES + 1
  segs.tick()
  local x = W - BEE_W
  core.text(x, 2, BEE_FRAMES[beeFrame][1], C.beeWing)
  local bodyText = BEE_FRAMES[beeFrame][2]
  if curSpecies and colors.glint(curSpecies) then
    -- glinting output: the purple window sweeps across the bee too
    local cx = x
    for _, r in ipairs(segs.sweep(bodyText, colors.of(curSpecies))) do
      core.text(cx, 3, r.text, r.color)
      cx = cx + #r.text
    end
  else
    local body = curSpecies and colors.of(curSpecies) or C.beeBody
    core.text(x, 3, bodyText, body)
  end
end

function ui.banner(text)
  if not core.hasGpu then print(text) return end
  core.fillRect(W - BEE_W, 2, BEE_W, 2)   -- the bee makes way
  core.fillRect(1, 2, W, 1, C.good)
  core.text(2, 2, core.clip(text), C.headerFg, C.good)
  core.cursorBottom()
end

ui.done          = core.finish
ui.sleep         = core.sleep
ui.haltRequested = core.haltRequested

return ui
