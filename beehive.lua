-- beehive.lua  ->  install to /lib/beehive.lua
-- The wide dashboard's hive pane: the queen going in, the bee flying
-- along a progress bar whose length is learned from earlier cycles
-- (a rolling average of the last ten), and elapsed / average / ETA.
-- With no average yet the bee patrols the bar instead.
--
-- Inner rows: 1 queen line, 2-3 bee, 4 bar, 5 timing.

local core     = require("beeui")
local segs     = require("beesegs")
local colors   = require("beecolors")
local computer = require("computer")
local C, g = core.C, core.g

local hive = {}

local P = nil
local BEE_W = 6
local BEE = {{" \\ /  ", "={;;}>"}, {" | |  ", "={;;}>"},
             {" / \\  ", "={;;}>"}, {" | |  ", "={;;}>"}}
local beeFrame = 0
local queenT0, durations = nil, {}

function hive.init(geo)
  P, queenT0, durations = geo, nil, {}
end

function hive.mmss(s)
  s = math.max(0, math.floor(s))
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function hive.avgCycle()
  if #durations == 0 then return nil end
  local sum = 0
  for _, d in ipairs(durations) do sum = sum + d end
  return sum / #durations
end

function hive.queenStart() queenT0 = computer.uptime() end

function hive.queenDone()
  if queenT0 then
    durations[#durations + 1] = computer.uptime() - queenT0
    if #durations > 10 then table.remove(durations, 1) end
  end
  queenT0 = nil
end

local function beeSeg(prefix, bee)
  local list = {{text = prefix, color = C.dim},
    {text = tostring(bee.active), species = bee.active}, {text = "/", color = C.dim},
    {text = tostring(bee.inactive), species = bee.inactive}}
  if bee.fertility then list[#list + 1] = {text = " f" .. bee.fertility, color = C.dim} end
  return list
end

function hive.pair(p, d)
  if not (P and core.hasGpu) then return end
  local list = {{text = "Queen  ", color = C.dim}}
  for _, s in ipairs(beeSeg("P ", p)) do list[#list + 1] = s end
  list[#list + 1] = {text = "   " .. g("times") .. "   ", color = C.dim}
  for _, s in ipairs(beeSeg("D ", d)) do list[#list + 1] = s end
  list[#list + 1] = {text = ("      slots %d %s %d"):format(p.slot or 0, g("mid"), d.slot or 0),
                     color = C.dim2}
  segs.set(P.y + 1, list, P.w - 2, P.x + 1)
end

-- One spinner tick: bee, bar and timing line
function hive.tick(species)
  if not (P and core.hasGpu) then return end
  local x0, w = P.x + 2, P.w - 4
  beeFrame = beeFrame % #BEE + 1
  local elapsed = queenT0 and (computer.uptime() - queenT0) or 0
  local avg = hive.avgCycle()
  local frac = 0
  if queenT0 and avg then
    frac = math.min(0.97, elapsed / avg)
  elseif queenT0 then
    local t = math.floor(elapsed) % (2 * w)
    frac = (t <= w and t or 2 * w - t) / w
  end
  local filled = math.floor(w * frac + 0.5)
  local col = species and colors.of(species) or C.beeBody
  core.fillRect(x0, P.y + 4, filled, 1, col)
  core.fillRect(x0 + filled, P.y + 4, w - filled, 1, C.barEmpty)
  core.fillRect(x0, P.y + 2, w, 2)
  local bx = x0 + math.max(0, math.min(w - BEE_W, filled - 3))
  core.text(bx, P.y + 2, BEE[beeFrame][1], C.beeWing)
  if species and colors.glint(species) then
    for _, r in ipairs(segs.sweep(BEE[beeFrame][2], col)) do
      core.text(bx, P.y + 3, r.text, r.color)
      bx = bx + core.len(r.text)
    end
  else
    core.text(bx, P.y + 3, BEE[beeFrame][2], col)
  end
  local t = queenT0 and (hive.mmss(elapsed) .. " elapsed") or "Between queens"
  if avg then
    t = t .. ("  %s  avg cycle %s"):format(g("mid"), hive.mmss(avg))
    if queenT0 then
      t = t .. ("  %s  ETA %s"):format(g("mid"), hive.mmss(avg - elapsed))
    end
  end
  core.line(P.y + 5, t, C.dim, P.w - 2, P.x + 1)
end

return hive
